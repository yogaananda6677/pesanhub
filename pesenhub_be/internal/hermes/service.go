package hermes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/order"
)

// OrderCreator creates a final order from a WhatsApp draft.
type OrderCreator interface {
	CreateWhatsApp(ctx context.Context, in order.WhatsAppOrderCreateInput, idempotencyKey, requestID string) (order.WhatsAppOrderResponse, bool, error)
}

// Service coordinates LLM extraction, catalog resolution, confidence policy, and audit logging.
type Service struct {
	client          LLMClient
	resolver        *CatalogResolver
	evaluator       *ConfidenceEvaluator
	store           RunStore
	convStore       ConversationStore
	clarifier       *ClarificationEngine
	merger          *DraftMerger
	catalogProvider CatalogProvider
	orderCreator    OrderCreator
	modelName       string
	promptVersion   string
}

// Config holds configuration options for Hermes Service.
type Config struct {
	Client              LLMClient
	CatalogProvider     CatalogProvider
	OrderCreator        OrderCreator
	Store               RunStore
	ConversationStore   ConversationStore
	ModelName           string
	PromptVersion       string
	ConfidenceThreshold float64
	MaxAttempts         int
}

// NewService creates a new Hermes Service.
func NewService(cfg Config) *Service {
	modelName := cfg.ModelName
	if modelName == "" {
		modelName = DefaultModelName
	}
	promptVer := cfg.PromptVersion
	if promptVer == "" {
		promptVer = PromptVersionV1
	}

	threshold := cfg.ConfidenceThreshold
	if threshold <= 0 {
		threshold = DefaultConfidenceThreshold
	}

	resolver := NewCatalogResolver(cfg.CatalogProvider)
	evaluator := NewConfidenceEvaluator(threshold)
	clarifier := NewClarificationEngine(cfg.MaxAttempts)
	merger := NewDraftMerger(cfg.CatalogProvider)

	convStore := cfg.ConversationStore
	if convStore == nil {
		convStore = NewMemoryConversationStore()
	}

	return &Service{
		client:          cfg.Client,
		resolver:        resolver,
		evaluator:       evaluator,
		store:           cfg.Store,
		convStore:       convStore,
		clarifier:       clarifier,
		merger:          merger,
		catalogProvider: cfg.CatalogProvider,
		orderCreator:    cfg.OrderCreator,
		modelName:       modelName,
		promptVersion:   promptVer,
	}
}

// ExtractOrder processes an inbound message to produce a catalog-grounded DraftCandidate and an AgentRun record.
func (s *Service) ExtractOrder(ctx context.Context, req ExtractionRequest) (*DraftCandidate, *AgentRun, error) {
	startTime := time.Now()
	toolCalls := make([]ToolCallAudit, 0)

	correlationID := strings.TrimSpace(req.CorrelationID)
	if correlationID == "" {
		correlationID = newID()
	}

	session := strings.TrimSpace(req.Session)
	if session == "" {
		session = "default"
	}

	// 1. Prompt Injection Defense
	if isInjected, reason := DetectPromptInjection(req.MessageText); isInjected {
		durationMs := int(time.Since(startTime).Milliseconds())
		ambiguityReasons := []string{"prompt_injection_detected", reason}
		errMsg := reason

		emptyDraft := &DraftCandidate{
			CustomerPhone:     req.SenderPhone,
			Items:             []ExtractedItem{},
			SubtotalAmount:    0,
			TotalAmount:       0,
			OverallConfidence: 0.0,
			IsAmbiguous:       true,
			AmbiguityReasons:  ambiguityReasons,
		}

		draftJSON, _ := json.Marshal(emptyDraft)
		toolsJSON, _ := json.Marshal(toolCalls)

		run := &AgentRun{
			ID:               newID(),
			InboundMessageID: req.InboundMessageID,
			Session:          session,
			CustomerPhone:    req.SenderPhone,
			Model:            s.modelName,
			PromptVersion:    s.promptVersion,
			ConfidenceScore:  0.0,
			IsAmbiguous:      true,
			AmbiguityReasons: ambiguityReasons,
			ExtractedDraft:   draftJSON,
			ToolCalls:        toolsJSON,
			DurationMs:       durationMs,
			Status:           StatusRejectedInjection,
			ErrorMessage:     &errMsg,
			CorrelationID:    correlationID,
			CreatedAt:        time.Now().UTC(),
		}

		if s.store != nil {
			_ = s.store.RecordRun(ctx, run)
		}

		return emptyDraft, run, nil
	}

	// 2. Prepare Prompts
	sysPrompt, userPrompt := BuildExtractionPrompt(req.MessageText)

	// 3. Invoke LLM
	llmStart := time.Now()
	rawOrder, err := s.client.ExtractOrder(ctx, sysPrompt, userPrompt)
	llmDurationMs := int(time.Since(llmStart).Milliseconds())

	llmAudit := ToolCallAudit{
		ToolName: "llm_extract_order",
		InputRedacted: map[string]any{
			"message_length": len(req.MessageText),
		},
		DurationMs: llmDurationMs,
	}

	if err != nil {
		llmAudit.Error = err.Error()
		toolCalls = append(toolCalls, llmAudit)
		toolsJSON, _ := json.Marshal(toolCalls)
		durationMs := int(time.Since(startTime).Milliseconds())
		errMsg := err.Error()

		run := &AgentRun{
			ID:               newID(),
			InboundMessageID: req.InboundMessageID,
			Session:          session,
			CustomerPhone:    req.SenderPhone,
			Model:            s.modelName,
			PromptVersion:    s.promptVersion,
			ConfidenceScore:  0.0,
			IsAmbiguous:      true,
			AmbiguityReasons: []string{"llm_extraction_error"},
			ExtractedDraft:   json.RawMessage("{}"),
			ToolCalls:        toolsJSON,
			DurationMs:       durationMs,
			Status:           StatusFailed,
			ErrorMessage:     &errMsg,
			CorrelationID:    correlationID,
			CreatedAt:        time.Now().UTC(),
		}

		if s.store != nil {
			_ = s.store.RecordRun(ctx, run)
		}

		return nil, run, fmt.Errorf("llm extraction failed: %w", err)
	}

	llmAudit.OutputRedacted = map[string]any{
		"items_count": len(rawOrder.Items),
		"confidence":  rawOrder.Confidence,
	}
	toolCalls = append(toolCalls, llmAudit)

	// 4. Resolve Items & Pricing against Active Catalog (Zero Hallucination)
	catStart := time.Now()
	resolveResult, err := s.resolver.ResolveOrder(ctx, rawOrder)
	catDurationMs := int(time.Since(catStart).Milliseconds())

	catAudit := ToolCallAudit{
		ToolName: "catalog_resolve_order",
		InputRedacted: map[string]any{
			"raw_items_count": len(rawOrder.Items),
		},
		DurationMs: catDurationMs,
	}

	if err != nil {
		catAudit.Error = err.Error()
		toolCalls = append(toolCalls, catAudit)
		toolsJSON, _ := json.Marshal(toolCalls)
		durationMs := int(time.Since(startTime).Milliseconds())
		errMsg := err.Error()

		run := &AgentRun{
			ID:               newID(),
			InboundMessageID: req.InboundMessageID,
			Session:          session,
			CustomerPhone:    req.SenderPhone,
			Model:            s.modelName,
			PromptVersion:    s.promptVersion,
			ConfidenceScore:  0.0,
			IsAmbiguous:      true,
			AmbiguityReasons: []string{"catalog_resolution_error"},
			ExtractedDraft:   json.RawMessage("{}"),
			ToolCalls:        toolsJSON,
			DurationMs:       durationMs,
			Status:           StatusFailed,
			ErrorMessage:     &errMsg,
			CorrelationID:    correlationID,
			CreatedAt:        time.Now().UTC(),
		}

		if s.store != nil {
			_ = s.store.RecordRun(ctx, run)
		}

		return nil, run, fmt.Errorf("catalog resolution failed: %w", err)
	}

	catAudit.OutputRedacted = map[string]any{
		"resolved_items_count": len(resolveResult.Items),
		"is_ambiguous":         resolveResult.IsAmbiguous,
	}
	toolCalls = append(toolCalls, catAudit)

	// 5. Evaluate Confidence & Ambiguity Policy
	overallScore, isAmbiguous, ambiguityReasons := s.evaluator.Evaluate(rawOrder, resolveResult)

	// 6. Build Draft Candidate
	var subtotal int64
	for _, it := range resolveResult.Items {
		subtotal += it.LineTotalAmount
	}

	draft := &DraftCandidate{
		CustomerPhone:     req.SenderPhone,
		Items:             resolveResult.Items,
		SubtotalAmount:    subtotal,
		TotalAmount:       subtotal,
		Notes:             strings.TrimSpace(rawOrder.Notes),
		FulfillmentType:   strings.TrimSpace(rawOrder.FulfillmentType),
		PaymentMethod:     strings.TrimSpace(rawOrder.PaymentMethod),
		OverallConfidence: overallScore,
		IsAmbiguous:       isAmbiguous,
		AmbiguityReasons:  ambiguityReasons,
	}

	status := StatusSuccess
	if isAmbiguous {
		status = StatusAmbiguous
	}

	draftJSON, _ := json.Marshal(draft)
	toolsJSON, _ := json.Marshal(toolCalls)
	durationMs := int(time.Since(startTime).Milliseconds())

	run := &AgentRun{
		ID:               newID(),
		InboundMessageID: req.InboundMessageID,
		Session:          session,
		CustomerPhone:    req.SenderPhone,
		Model:            s.modelName,
		PromptVersion:    s.promptVersion,
		ConfidenceScore:  overallScore,
		IsAmbiguous:      isAmbiguous,
		AmbiguityReasons: ambiguityReasons,
		ExtractedDraft:   draftJSON,
		ToolCalls:        toolsJSON,
		DurationMs:       durationMs,
		Status:           status,
		CorrelationID:    correlationID,
		CreatedAt:        time.Now().UTC(),
	}

	if s.store != nil {
		_ = s.store.RecordRun(ctx, run)
	}

	return draft, run, nil
}

// ProcessTurn processes an inbound turn in a conversation session, deciding whether to ask clarification, trigger handoff, or confirm order.
func (s *Service) ProcessTurn(ctx context.Context, req TurnRequest) (*TurnResponse, error) {
	correlationID := strings.TrimSpace(req.CorrelationID)
	if correlationID == "" {
		correlationID = newID()
	}

	session := strings.TrimSpace(req.Session)
	if session == "" {
		session = "default"
	}

	state, err := s.convStore.GetOrCreate(ctx, session, req.SenderPhone, correlationID)
	if err != nil {
		return nil, fmt.Errorf("failed to get or create conversation state: %w", err)
	}
	state.LastInboundMessageID = req.InboundMessageID
	state.CorrelationID = correlationID

	// 1. Check automation pause / active handoff gate (Zero Auto-Reply during takeover)
	if state.IsPaused || state.Status == ConversationHandoff || state.Status == ConversationPaused {
		_ = s.convStore.Save(ctx, state)
		return &TurnResponse{
			State:            state,
			Draft:            state.CurrentDraft,
			ReplyText:        "",
			RequiresHandoff:  true,
			HandledByAgent:   false,
			AutomationPaused: true,
		}, nil
	}

	categories, err := s.catalogProvider.ListPublic(ctx, "")
	if err != nil {
		return nil, fmt.Errorf("failed to list catalog: %w", err)
	}

	// 2. Check prompt injection immediately
	if isInjected, reason := DetectPromptInjection(req.MessageText); isInjected {
		state.Status = ConversationHandoff
		state.HandoffStatus = HandoffStatusPending
		state.HandoffReason = &reason
		state.HandoffPriority = HandoffPriorityHigh
		state.PendingAmbiguity = "prompt_injection_detected"
		state.LastQuestion = "Mohon maaf kak, permintaan tersebut tidak dapat kami proses. Percakapan ini kami alihkan ke staf kami."
		_ = s.convStore.Save(ctx, state)
		s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": HandoffPriorityHigh})

		run := &AgentRun{
			ID:               newID(),
			InboundMessageID: req.InboundMessageID,
			Session:          session,
			CustomerPhone:    req.SenderPhone,
			Model:            s.modelName,
			PromptVersion:    s.promptVersion,
			ConfidenceScore:  0.0,
			IsAmbiguous:      true,
			AmbiguityReasons: []string{"prompt_injection_detected", reason},
			DurationMs:       0,
			Status:           StatusRejectedInjection,
			ErrorMessage:     &reason,
			CorrelationID:    correlationID,
			CreatedAt:        time.Now().UTC(),
		}
		if s.store != nil {
			_ = s.store.RecordRun(ctx, run)
		}

		return &TurnResponse{
			State:            state,
			ReplyText:        state.LastQuestion,
			RequiresHandoff:  true,
			HandledByAgent:   false,
			AutomationPaused: true,
			Run:              run,
		}, nil
	}

	// 3. Check customer complaint or human staff takeover request
	if isComplaint, reason, priority := DetectComplaint(req.MessageText); isComplaint {
		state.Status = ConversationHandoff
		state.HandoffStatus = HandoffStatusPending
		state.HandoffReason = &reason
		state.HandoffPriority = priority
		state.PendingAmbiguity = reason
		reply := "Mohon maaf atas ketidaknyamanannya kak. Percakapan ini kami alihkan ke staf kami untuk segera menindaklanjuti keluhan kakak."
		if reason == "customer_requested_human" {
			reply = "Baik kak, pesanan ini kami jeda dan segera kami hubungkan dengan staf kami untuk membantu langsung."
		}
		state.LastQuestion = reply
		_ = s.convStore.Save(ctx, state)
		s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": priority})

		return &TurnResponse{
			State:            state,
			Draft:            state.CurrentDraft,
			ReplyText:        reply,
			RequiresHandoff:  true,
			HandledByAgent:   false,
			AutomationPaused: true,
		}, nil
	}

	// 4. Check out of scope inquiries (loans, jobs, vehicle mechanic, etc.)
	if isOOS, reason, priority := DetectOutOfScope(req.MessageText); isOOS {
		state.Status = ConversationHandoff
		state.HandoffStatus = HandoffStatusPending
		state.HandoffReason = &reason
		state.HandoffPriority = priority
		state.PendingAmbiguity = reason
		reply := "Mohon maaf kak, sistem otomatis kami hanya melayani pemesanan menu makanan dan minuman. Percakapan ini kami teruskan ke staf kami jika ada keperluan lain."
		state.LastQuestion = reply
		_ = s.convStore.Save(ctx, state)
		s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": priority})

		return &TurnResponse{
			State:            state,
			Draft:            state.CurrentDraft,
			ReplyText:        reply,
			RequiresHandoff:  true,
			HandledByAgent:   false,
			AutomationPaused: true,
		}, nil
	}

	// 5. If currently awaiting clarification:
	if state.Status == ConversationAwaitingClarification && state.CurrentDraft != nil {
		updatedDraft, resolved, err := s.merger.MergeClarification(ctx, state.CurrentDraft, state.PendingAmbiguity, req.MessageText, categories)
		if err != nil {
			return nil, fmt.Errorf("failed to merge clarification: %w", err)
		}

		if !resolved {
			// Clarification attempt failed
			state.ClarificationAttempts++
			plan := s.clarifier.PlanClarification(updatedDraft, state.ClarificationAttempts, categories)
			if plan.RequiresHandoff {
				state.Status = ConversationHandoff
				state.HandoffStatus = HandoffStatusPending
				reason := plan.HandoffReason
				if reason == "" {
					reason = "max_clarification_attempts_exceeded"
				}
				state.HandoffReason = &reason
				state.HandoffPriority = HandoffPriorityNormal
				state.LastQuestion = plan.QuestionText
				_ = s.convStore.Save(ctx, state)
				s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": HandoffPriorityNormal})

				return &TurnResponse{
					State:            state,
					Draft:            updatedDraft,
					ReplyText:        plan.QuestionText,
					RequiresHandoff:  true,
					HandledByAgent:   false,
					AutomationPaused: true,
				}, nil
			}

			state.LastQuestion = plan.QuestionText
			state.PendingAmbiguity = plan.PriorityAmbiguity
			state.CurrentDraft = updatedDraft
			_ = s.convStore.Save(ctx, state)

			return &TurnResponse{
				State:            state,
				Draft:            updatedDraft,
				ReplyText:        plan.QuestionText,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
			}, nil
		}

		// Resolved! Check if any remaining ambiguities
		plan := s.clarifier.PlanClarification(updatedDraft, 0, categories)
		if plan.RequiresClarification {
			// Ask next priority ambiguity
			state.Status = ConversationAwaitingClarification
			state.CurrentDraft = updatedDraft
			state.PendingAmbiguity = plan.PriorityAmbiguity
			state.LastQuestion = plan.QuestionText
			state.ClarificationAttempts = 0 // reset attempts for the new question
			_ = s.convStore.Save(ctx, state)

			return &TurnResponse{
				State:            state,
				Draft:            updatedDraft,
				ReplyText:        plan.QuestionText,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
			}, nil
		}

		// Unambiguous and complete!
		state.Status = ConversationReadyForConfirmation
		state.CurrentDraft = updatedDraft
		state.PendingAmbiguity = ""
		state.LastQuestion = ""
		state.ClarificationAttempts = 0
		state.ToolFailureCount = 0
		state.DraftVersion++
		state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
		summaryText := formatOrderSummary(updatedDraft)
		state.LastQuestion = summaryText
		_ = s.convStore.Save(ctx, state)

		return &TurnResponse{
			State:            state,
			Draft:            updatedDraft,
			ReplyText:        summaryText,
			RequiresHandoff:  false,
			HandledByAgent:   true,
			AutomationPaused: false,
		}, nil
	}

	// 6. If currently ready for confirmation:
	if state.Status == ConversationReadyForConfirmation && state.CurrentDraft != nil {
		intent := DetectConfirmationIntent(req.MessageText)
		switch intent {
		case IntentConfirm:
			// 1. Revalidate draft against current catalog (Zero Stale / Price Change)
			isFresh, updatedDraft, changeReason := ValidateDraftFreshness(ctx, state.CurrentDraft, categories)
			if !isFresh {
				state.CurrentDraft = updatedDraft
				state.DraftVersion++
				state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
				replyText := fmt.Sprintf("Mohon maaf kak, terdapat perubahan: %s.\nTotal pesanan baru adalah Rp %d.\n\nApakah kakak setuju melanjutkan pesanan dengan total baru ini? (Ketik Ya untuk konfirmasi, atau Batal untuk membatalkan)", changeReason, updatedDraft.TotalAmount)
				state.LastQuestion = replyText
				_ = s.convStore.Save(ctx, state)

				return &TurnResponse{
					State:            state,
					Draft:            updatedDraft,
					ReplyText:        replyText,
					RequiresHandoff:  false,
					HandledByAgent:   true,
					AutomationPaused: false,
				}, nil
			}

			// 2. Draft is fresh! Create WhatsApp order idempotently
			if s.orderCreator == nil {
				return nil, errors.New("order creator unavailable")
			}

			orderItems := make([]order.ItemInput, 0, len(state.CurrentDraft.Items))
			for _, it := range state.CurrentDraft.Items {
				var selections []catalog.Selection
				groupOptions := make(map[string][]string)
				for _, mod := range it.SelectedModifiers {
					groupOptions[mod.GroupID] = append(groupOptions[mod.GroupID], mod.OptionID)
				}
				for gID, optIDs := range groupOptions {
					selections = append(selections, catalog.Selection{
						GroupID:   gID,
						OptionIDs: optIDs,
					})
				}
				orderItems = append(orderItems, order.ItemInput{
					MenuID:     it.MenuID,
					Quantity:   it.Quantity,
					Notes:      it.Notes,
					Selections: selections,
				})
			}

			idempotencyKey := fmt.Sprintf("wa-conf-%s-%d", state.ID, state.DraftVersion)
			createIn := order.WhatsAppOrderCreateInput{
				CustomerPhone: req.SenderPhone,
				CustomerName:  "Pelanggan WhatsApp",
				Notes:         state.CurrentDraft.Notes,
				Items:         orderItems,
			}

			orderRes, _, err := s.orderCreator.CreateWhatsApp(ctx, createIn, idempotencyKey, correlationID)
			if err != nil {
				state.ToolFailureCount++
				if state.ToolFailureCount >= MaxToolFailures {
					state.Status = ConversationHandoff
					state.HandoffStatus = HandoffStatusPending
					reason := "order_creation_failed"
					state.HandoffReason = &reason
					state.HandoffPriority = HandoffPriorityHigh
					reply := "Mohon maaf kak, sistem kami mengalami kendala teknis saat memproses pesanan kakak. Percakapan ini kami alihkan ke staf kami."
					state.LastQuestion = reply
					_ = s.convStore.Save(ctx, state)
					s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{
						"priority": HandoffPriorityHigh,
						"error":    err.Error(),
					})

					return &TurnResponse{
						State:            state,
						Draft:            state.CurrentDraft,
						ReplyText:        reply,
						RequiresHandoff:  true,
						HandledByAgent:   false,
						AutomationPaused: true,
					}, nil
				}
				_ = s.convStore.Save(ctx, state)
				return nil, fmt.Errorf("failed to create whatsapp order: %w", err)
			}

			state.ToolFailureCount = 0
			state.Status = ConversationCompleted
			state.LastOrderID = &orderRes.ID
			state.LastQuestion = ""
			_ = s.convStore.Save(ctx, state)

			orderSummary := &WhatsAppOrderSummary{
				ID:                  orderRes.ID,
				OrderNumber:         orderRes.OrderNumber,
				PublicTrackingToken: orderRes.PublicTrackingToken,
				Status:              orderRes.Status,
				TotalAmount:         orderRes.TotalAmount,
				CreatedAt:           orderRes.CreatedAt,
			}

			successReply := FormatOrderSuccessMessage(orderRes.OrderNumber, orderRes.PublicTrackingToken, orderRes.TotalAmount)
			return &TurnResponse{
				State:            state,
				Draft:            state.CurrentDraft,
				ReplyText:        successReply,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
				Order:            orderSummary,
			}, nil

		case IntentCancel:
			state.Status = ConversationCollecting
			state.CurrentDraft = nil
			state.ConfirmationToken = ""
			state.DraftVersion = 1
			state.PendingAmbiguity = ""
			state.LastQuestion = ""
			_ = s.convStore.Save(ctx, state)

			reply := "Baik kak, draft pesanan telah dibatalkan. Jika ingin memesan kembali di lain waktu, silakan hubungi kami lagi ya!"
			return &TurnResponse{
				State:            state,
				ReplyText:        reply,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
			}, nil

		case IntentModify:
			newDraft, run, err := s.ExtractOrder(ctx, ExtractionRequest{
				InboundMessageID: req.InboundMessageID,
				MessageText:      req.MessageText,
				SenderPhone:      req.SenderPhone,
				CorrelationID:    correlationID,
				Session:          session,
			})
			if err != nil {
				reply := "Mohon maaf kak, kami belum memahami perubahan yang dimaksud. Silakan sebutkan kembali menu dan jumlah yang ingin dipesan, atau ketik Ya untuk melanjutkan pesanan sebelumnya."
				return &TurnResponse{
					State:            state,
					Draft:            state.CurrentDraft,
					ReplyText:        reply,
					RequiresHandoff:  false,
					HandledByAgent:   true,
					AutomationPaused: false,
				}, nil
			}
			plan := s.clarifier.PlanClarification(newDraft, 0, categories)
			if plan.RequiresClarification {
				state.Status = ConversationAwaitingClarification
				state.CurrentDraft = newDraft
				state.PendingAmbiguity = plan.PriorityAmbiguity
				state.LastQuestion = plan.QuestionText
				state.ClarificationAttempts = 0
				state.DraftVersion++
				_ = s.convStore.Save(ctx, state)

				return &TurnResponse{
					State:            state,
					Draft:            newDraft,
					ReplyText:        plan.QuestionText,
					RequiresHandoff:  false,
					HandledByAgent:   true,
					AutomationPaused: false,
					Run:              run,
				}, nil
			}

			state.Status = ConversationReadyForConfirmation
			state.CurrentDraft = newDraft
			state.PendingAmbiguity = ""
			state.ClarificationAttempts = 0
			state.DraftVersion++
			state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
			summaryText := formatOrderSummary(newDraft)
			state.LastQuestion = summaryText
			_ = s.convStore.Save(ctx, state)

			return &TurnResponse{
				State:            state,
				Draft:            newDraft,
				ReplyText:        summaryText,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
				Run:              run,
			}, nil

		case IntentUnknown:
			reply := "Pesanan kakak belum terkonfirmasi. Silakan ketik *Ya* untuk melanjutkan pembuatan pesanan, atau ketik *Batal* untuk membatalkan."
			state.LastQuestion = reply
			_ = s.convStore.Save(ctx, state)

			return &TurnResponse{
				State:            state,
				Draft:            state.CurrentDraft,
				ReplyText:        reply,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
			}, nil
		}
	}

	// 7. If currently completed:
	if state.Status == ConversationCompleted {
		lower := strings.ToLower(strings.TrimSpace(req.MessageText))
		if lower == "terima kasih" || lower == "makasih" || lower == "terimakasih" || lower == "tq" || lower == "ok" || lower == "oke" || lower == "siap" {
			return &TurnResponse{
				State:            state,
				ReplyText:        "Sama-sama kak! Pesanan kakak sedang kami siapkan.",
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
			}, nil
		}
		// Reset to start a new order
		state.Status = ConversationCollecting
		state.CurrentDraft = nil
		state.PendingAmbiguity = ""
		state.ClarificationAttempts = 0
		state.LastQuestion = ""
		state.ConfirmationToken = ""
		state.DraftVersion = 1
	}

	// 6. Initial message / Collecting state
	draft, run, err := s.ExtractOrder(ctx, ExtractionRequest{
		InboundMessageID: req.InboundMessageID,
		MessageText:      req.MessageText,
		SenderPhone:      req.SenderPhone,
		CorrelationID:    correlationID,
		Session:          session,
	})
	if err != nil {
		state.ToolFailureCount++
		if state.ToolFailureCount >= MaxToolFailures {
			state.Status = ConversationHandoff
			state.HandoffStatus = HandoffStatusPending
			reason := "repeated_tool_failure"
			state.HandoffReason = &reason
			state.HandoffPriority = HandoffPriorityHigh
			reply := "Mohon maaf kak, sistem kami sedang mengalami gangguan teknis saat memproses pesanan. Percakapan ini kami alihkan ke staf kami."
			state.LastQuestion = reply
			_ = s.convStore.Save(ctx, state)
			s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{
				"priority":      HandoffPriorityHigh,
				"failure_count": state.ToolFailureCount,
			})

			return &TurnResponse{
				State:            state,
				Draft:            state.CurrentDraft,
				ReplyText:        reply,
				RequiresHandoff:  true,
				HandledByAgent:   false,
				AutomationPaused: true,
				Run:              run,
			}, nil
		}
		_ = s.convStore.Save(ctx, state)
		return nil, err
	}

	state.ToolFailureCount = 0

	plan := s.clarifier.PlanClarification(draft, 0, categories)
	if plan.RequiresHandoff {
		state.Status = ConversationHandoff
		state.HandoffStatus = HandoffStatusPending
		reason := plan.HandoffReason
		if reason == "" {
			reason = "clarification_plan_handoff"
		}
		state.HandoffReason = &reason
		state.HandoffPriority = HandoffPriorityNormal
		state.CurrentDraft = draft
		state.LastQuestion = plan.QuestionText
		_ = s.convStore.Save(ctx, state)
		s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": HandoffPriorityNormal})

		return &TurnResponse{
			State:            state,
			Draft:            draft,
			ReplyText:        plan.QuestionText,
			RequiresHandoff:  true,
			HandledByAgent:   false,
			AutomationPaused: true,
			Run:              run,
		}, nil
	}

	if plan.RequiresClarification {
		state.Status = ConversationAwaitingClarification
		state.CurrentDraft = draft
		state.PendingAmbiguity = plan.PriorityAmbiguity
		state.LastQuestion = plan.QuestionText
		state.ClarificationAttempts = 0
		_ = s.convStore.Save(ctx, state)

		return &TurnResponse{
			State:            state,
			Draft:            draft,
			ReplyText:        plan.QuestionText,
			RequiresHandoff:  false,
			HandledByAgent:   true,
			AutomationPaused: false,
			Run:              run,
		}, nil
	}

	// Complete on first turn
	state.Status = ConversationReadyForConfirmation
	state.CurrentDraft = draft
	state.PendingAmbiguity = ""
	state.LastQuestion = ""
	state.ClarificationAttempts = 0
	state.DraftVersion = 1
	state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
	summaryText := formatOrderSummary(draft)
	state.LastQuestion = summaryText
	_ = s.convStore.Save(ctx, state)

	return &TurnResponse{
		State:            state,
		Draft:            draft,
		ReplyText:        summaryText,
		RequiresHandoff:  false,
		HandledByAgent:   true,
		AutomationPaused: false,
		Run:              run,
	}, nil
}

func formatOrderSummary(draft *DraftCandidate) string {
	var sb strings.Builder
	sb.WriteString("Berikut ringkasan pesanan kak:\n")
	for _, it := range draft.Items {
		var modNames []string
		for _, m := range it.SelectedModifiers {
			modNames = append(modNames, m.OptionName)
		}
		modStr := ""
		if len(modNames) > 0 {
			modStr = fmt.Sprintf(" (%s)", strings.Join(modNames, ", "))
		}
		sb.WriteString(fmt.Sprintf("- %d %s%s: Rp %d\n", it.Quantity, it.Name, modStr, it.LineTotalAmount))
	}
	sb.WriteString(fmt.Sprintf("\nTotal: Rp %d\n", draft.SubtotalAmount))
	fulfillment := draft.FulfillmentType
	if fulfillment == "" {
		fulfillment = "PICKUP"
	}
	sb.WriteString(fmt.Sprintf("Pengambilan: %s\n", fulfillment))
	sb.WriteString("Pembayaran: Tunai / QRIS saat pengambilan\n")
	sb.WriteString("\nApakah pesanan sudah sesuai kak? (Ketik Ya untuk konfirmasi, atau Batal untuk membatalkan)")
	return sb.String()
}

func (s *Service) recordHandoffAudit(ctx context.Context, state *ConversationState, action, actor, role, reason, correlationID string, metaMap map[string]any) {
	if s.convStore == nil {
		return
	}
	var metaBytes []byte
	if metaMap != nil {
		metaBytes, _ = json.Marshal(metaMap)
	} else {
		metaBytes = []byte("{}")
	}
	_ = s.convStore.RecordAuditEvent(ctx, &ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        state.Session,
		CustomerPhone:  state.CustomerPhone,
		Action:         action,
		Actor:          actor,
		ActorRole:      role,
		Reason:         reason,
		Metadata:       metaBytes,
		CorrelationID:  correlationID,
		CreatedAt:      time.Now().UTC(),
	})
}

// PauseConversation explicitly pauses agent automation for a customer conversation.
func (s *Service) PauseConversation(ctx context.Context, session, customerPhone, actor, role, reason, correlationID string) (*ConversationState, error) {
	if s.convStore == nil {
		return nil, errors.New("conversation store unavailable")
	}
	return s.convStore.Pause(ctx, session, customerPhone, actor, role, reason, correlationID)
}

// ResumeConversation resumes agent automation for a customer conversation without replaying past messages.
func (s *Service) ResumeConversation(ctx context.Context, session, customerPhone, actor, role, reason, correlationID string) (*ConversationState, error) {
	if s.convStore == nil {
		return nil, errors.New("conversation store unavailable")
	}
	return s.convStore.Resume(ctx, session, customerPhone, actor, role, reason, correlationID)
}

// AssignConversation assigns a staff member to handle an active handoff.
func (s *Service) AssignConversation(ctx context.Context, session, customerPhone, actor, role, assignedTo, correlationID string) (*ConversationState, error) {
	if s.convStore == nil {
		return nil, errors.New("conversation store unavailable")
	}
	return s.convStore.Assign(ctx, session, customerPhone, actor, role, assignedTo, correlationID)
}

// ResolveConversation marks a handoff as resolved, optionally reactivating automated order-taking.
func (s *Service) ResolveConversation(ctx context.Context, session, customerPhone, actor, role, resolution string, resumeAutomation bool, correlationID string) (*ConversationState, error) {
	if s.convStore == nil {
		return nil, errors.New("conversation store unavailable")
	}
	return s.convStore.Resolve(ctx, session, customerPhone, actor, role, resolution, resumeAutomation, correlationID)
}

// ListHandoffQueue returns conversations that need staff attention.
func (s *Service) ListHandoffQueue(ctx context.Context, filter HandoffQueueFilter) ([]HandoffQueueItem, int, error) {
	if s.convStore == nil {
		return nil, 0, errors.New("conversation store unavailable")
	}
	return s.convStore.ListHandoffQueue(ctx, filter)
}

// GetAuditLogs returns the audit trail of handoff events for a conversation.
func (s *Service) GetAuditLogs(ctx context.Context, conversationID string) ([]ConversationAuditEvent, error) {
	if s.convStore == nil {
		return nil, errors.New("conversation store unavailable")
	}
	return s.convStore.GetAuditEvents(ctx, conversationID)
}
