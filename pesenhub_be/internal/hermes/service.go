package hermes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
	"unicode"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/order"
	"pesenhub/backend/internal/receipt"
)

// OrderCreator creates a final order from a WhatsApp draft.
type OrderCreator interface {
	CreateWhatsApp(ctx context.Context, in order.WhatsAppOrderCreateInput, idempotencyKey, requestID string) (order.WhatsAppOrderResponse, bool, error)
}

// OrderReader queries order details for customer status inquiries.
type OrderReader interface {
	GetByID(ctx context.Context, orderID string) (order.OrderDetail, error)
	GetLatestByPhone(ctx context.Context, phone string) (order.OrderDetail, error)
}

// CustomerMemory defines methods needed to remember and retrieve customer names by phone number.
type CustomerMemory interface {
	GetByPhone(ctx context.Context, phone string) (*customer.Profile, error)
	UpsertName(ctx context.Context, phone, name string) (*customer.Profile, error)
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
	orderReader     OrderReader
	customerMemory  CustomerMemory
	modelName       string
	promptVersion   string
}

// Config holds configuration options for Hermes Service.
type Config struct {
	Client              LLMClient
	CatalogProvider     CatalogProvider
	OrderCreator        OrderCreator
	OrderReader         OrderReader
	CustomerMemory      CustomerMemory
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
		orderReader:     cfg.OrderReader,
		customerMemory:  cfg.CustomerMemory,
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
	pCtx := req.PromptContext
	if pCtx.CustomerName == "" {
		pCtx.CustomerName = req.CustomerName
	}
	sysPrompt, userPrompt := BuildExtractionPromptWithFullContext(req.MessageText, pCtx)

	// 3. Invoke LLM
	llmStart := time.Now()
	agentCtx := WithAgentSession(ctx, session, req.SenderPhone)
	rawOrder, err := s.client.ExtractOrder(agentCtx, sysPrompt, userPrompt)
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

	resolvedCustomerName := req.CustomerName
	if resolvedCustomerName == "" && rawOrder.CustomerName != "" {
		resolvedCustomerName = cleanCustomerName(rawOrder.CustomerName)
	}

	draft := &DraftCandidate{
		CustomerPhone:     req.SenderPhone,
		CustomerName:      resolvedCustomerName,
		Items:             resolveResult.Items,
		SubtotalAmount:    subtotal,
		TotalAmount:       subtotal,
		Notes:             strings.TrimSpace(rawOrder.Notes),
		FulfillmentType:   "PICKUP",
		PaymentMethod:     "CASH",
		OverallConfidence: overallScore,
		IsAmbiguous:       isAmbiguous,
		AmbiguityReasons:  ambiguityReasons,
		ReplyText:         strings.TrimSpace(rawOrder.ReplyText),
	}
	if strings.TrimSpace(rawOrder.FulfillmentType) != "" {
		draft.FulfillmentType = strings.TrimSpace(rawOrder.FulfillmentType)
	}
	if strings.TrimSpace(rawOrder.PaymentMethod) != "" {
		draft.PaymentMethod = strings.TrimSpace(rawOrder.PaymentMethod)
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
	startTime := time.Now()
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

	// Resolve and remember customer identity
	if req.CustomerName != "" && state.CustomerName == "" {
		if cleaned := cleanCustomerName(req.CustomerName); cleaned != "" {
			state.CustomerName = cleaned
		}
	}
	if extractedName := ExtractCustomerName(req.MessageText); extractedName != "" {
		state.CustomerName = extractedName
		if s.customerMemory != nil {
			_, _ = s.customerMemory.UpsertName(ctx, req.SenderPhone, extractedName)
		}
	} else if state.CustomerName == "" && s.customerMemory != nil {
		if profile, err := s.customerMemory.GetByPhone(ctx, req.SenderPhone); err == nil && profile != nil && profile.DisplayName != "" {
			state.CustomerName = profile.DisplayName
		}
	}

	// 1. Check automation pause / active handoff gate (Zero Auto-Reply during takeover)
	// If a human staff is actively assigned (AssignedTo is set), respect staff takeover.
	// But if it's an unassigned automated handoff (HandoffStatusPending) AND:
	//   a) The customer sends a new message after inactivity (> 10 minutes), OR
	//   b) The customer asks for catalog, menu, store info, recommendation, or sends a greeting,
	// then auto-recover: reset handoff to Collecting, clear clarification counter, and allow AI to assist!
	if state.Status == ConversationHandoff && (state.AssignedTo == nil || *state.AssignedTo == "") {
		isStale := time.Since(state.UpdatedAt) > 10*time.Minute
		isInfo, _ := DetectStoreInfoInquiry(req.MessageText)
		isNewInquiry := DetectGreetingInquiry(req.MessageText) ||
			DetectCatalogInquiry(req.MessageText) ||
			isInfo ||
			DetectRecommendationInquiry(req.MessageText) ||
			DetectOrderStatusInquiry(req.MessageText)

		if isStale || isNewInquiry {
			state.Status = ConversationCollecting
			state.HandoffStatus = HandoffStatusNone
			state.HandoffReason = nil
			state.ClarificationAttempts = 0
			state.CurrentDraft = nil
			state.PendingAmbiguity = ""
			state.LastQuestion = ""
			_ = s.convStore.Save(ctx, state)
			s.recordHandoffAudit(ctx, state, HandoffActionResolved, "SYSTEM", "SYSTEM", "auto_resumed_new_inquiry", correlationID, nil)
		}
	}

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
		state.LastQuestion = personalizeCustomerGreeting("Mohon maaf kak, permintaan tersebut tidak dapat kami proses. Percakapan ini kami alihkan ke staf kami.", state.CustomerName)
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
		reply := personalizeCustomerGreeting("Mohon maaf atas ketidaknyamanannya kak. Percakapan ini kami alihkan ke staf kami untuk segera menindaklanjuti keluhan kakak.", state.CustomerName)
		if reason == "customer_requested_human" {
			reply = personalizeCustomerGreeting("Baik kak, pesanan ini kami jeda dan segera kami hubungkan dengan staf kami untuk membantu langsung.", state.CustomerName)
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
		reply := personalizeCustomerGreeting("Mohon maaf kak, sistem otomatis kami hanya melayani pemesanan menu makanan dan minuman. Percakapan ini kami teruskan ke staf kami jika ada keperluan lain.", state.CustomerName)
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

	// 4a. Receipt / struk inquiry (e.g. "minta struknya dong kak", "kirim struk")
	if DetectReceiptInquiry(req.MessageText) {
		var activeOrder *order.OrderDetail
		if state.LastOrderID != nil && *state.LastOrderID != "" && s.orderReader != nil {
			if ord, err := s.orderReader.GetByID(ctx, *state.LastOrderID); err == nil && ord.ID != "" {
				activeOrder = &ord
			}
		}
		if activeOrder == nil && s.orderReader != nil {
			if ord, err := s.orderReader.GetLatestByPhone(ctx, req.SenderPhone); err == nil && ord.ID != "" {
				activeOrder = &ord
			}
		}

		var reply string
		var mediaAttachments []MediaAttachment
		if activeOrder != nil {
			greeting := "kak"
			if state.CustomerName != "" {
				greeting = "kak " + state.CustomerName
			}
			reply = fmt.Sprintf("Ini struk resmi pesanan #%s kakak ya %s 😊 Terima kasih!", activeOrder.OrderNumber, greeting)
			if receiptAtt := buildReceiptMediaAttachment(*activeOrder, state.CustomerName); receiptAtt != nil {
				mediaAttachments = append(mediaAttachments, *receiptAtt)
			}
		} else {
			reply = formatNoActiveOrderMessage(state.CustomerName)
		}

		state.LastQuestion = reply
		_ = s.convStore.Save(ctx, state)

		durationMs := int(time.Since(startTime).Milliseconds())
		run := &AgentRun{
			ID:               newID(),
			InboundMessageID: req.InboundMessageID,
			Session:          session,
			CustomerPhone:    req.SenderPhone,
			Model:            s.modelName,
			PromptVersion:    s.promptVersion,
			ConfidenceScore:  1.0,
			IsAmbiguous:      false,
			AmbiguityReasons: []string{},
			DurationMs:       durationMs,
			Status:           StatusSuccess,
			CorrelationID:    correlationID,
			CreatedAt:        time.Now().UTC(),
		}
		if s.store != nil {
			_ = s.store.RecordRun(ctx, run)
		}

		return &TurnResponse{
			State:            state,
			Draft:            state.CurrentDraft,
			ReplyText:        reply,
			RequiresHandoff:  false,
			HandledByAgent:   true,
			AutomationPaused: false,
			Run:              run,
			MediaAttachments: mediaAttachments,
		}, nil
	}

	// Dynamic operational and customer context injection for natural conversational AI
	pCtx := s.buildPromptContext(ctx, req, state)

	// 5. If currently awaiting clarification:
	if state.Status == ConversationAwaitingClarification && state.CurrentDraft != nil {
		// If the previous draft was empty (from greeting/chitchat), this message is an order,
		// so run full LLM extraction.
		if len(state.CurrentDraft.Items) == 0 || state.PendingAmbiguity == "empty_order_items" || state.PendingAmbiguity == "empty_draft" || state.PendingAmbiguity == "no_valid_items_resolved" {
			newDraft, run, extractErr := s.ExtractOrder(ctx, ExtractionRequest{
				InboundMessageID: req.InboundMessageID,
				MessageText:      req.MessageText,
				SenderPhone:      req.SenderPhone,
				CustomerName:     state.CustomerName,
				CorrelationID:    correlationID,
				Session:          session,
				PromptContext:    pCtx,
			})
			if extractErr == nil && len(newDraft.Items) == 0 {
				reply := newDraft.ReplyText
				var mediaAttachments []MediaAttachment
				if reply == "" {
					reply, mediaAttachments = s.fallbackConversationalReply(ctx, req, state, categories)
				} else if DetectCatalogInquiry(req.MessageText) {
					mediaAttachments = getCatalogMediaAttachments()
				}
				state.LastQuestion = reply
				_ = s.convStore.Save(ctx, state)

				return &TurnResponse{
					State:            state,
					Draft:            state.CurrentDraft,
					ReplyText:        reply,
					RequiresHandoff:  false,
					HandledByAgent:   true,
					AutomationPaused: false,
					Run:              run,
					MediaAttachments: mediaAttachments,
				}, nil
			}
			if extractErr == nil && len(newDraft.Items) > 0 {
				plan := s.clarifier.PlanClarification(newDraft, 0, categories)
				if plan.RequiresHandoff {
					state.Status = ConversationHandoff
					state.HandoffStatus = HandoffStatusPending
					reason := plan.HandoffReason
					if reason == "" {
						reason = "clarification_plan_handoff"
					}
					state.HandoffReason = &reason
					state.HandoffPriority = HandoffPriorityNormal
					state.CurrentDraft = newDraft
					replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
					state.LastQuestion = replyQ
					_ = s.convStore.Save(ctx, state)
					s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": HandoffPriorityNormal})

					return &TurnResponse{
						State:            state,
						Draft:            newDraft,
						ReplyText:        replyQ,
						RequiresHandoff:  true,
						HandledByAgent:   false,
						AutomationPaused: true,
						Run:              run,
					}, nil
				}

				if plan.RequiresClarification {
					state.Status = ConversationAwaitingClarification
					state.CurrentDraft = newDraft
					state.PendingAmbiguity = plan.PriorityAmbiguity
					replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
					state.LastQuestion = replyQ
					state.ClarificationAttempts = 0
					_ = s.convStore.Save(ctx, state)

					return &TurnResponse{
						State:            state,
						Draft:            newDraft,
						ReplyText:        replyQ,
						RequiresHandoff:  false,
						HandledByAgent:   true,
						AutomationPaused: false,
						Run:              run,
					}, nil
				}

				// Unambiguous and complete!
				state.Status = ConversationReadyForConfirmation
				state.CurrentDraft = newDraft
				state.PendingAmbiguity = ""
				state.LastQuestion = ""
				state.ClarificationAttempts = 0
				state.ToolFailureCount = 0
				state.DraftVersion++
				state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
				summaryText := formatOrderSummary(newDraft, state.CustomerName)
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
			}
		}

		updatedDraft, resolved, err := s.merger.MergeClarification(ctx, state.CurrentDraft, state.PendingAmbiguity, req.MessageText, categories)
		if err != nil {
			return nil, fmt.Errorf("failed to merge clarification: %w", err)
		}

		if !resolved {
			// Before repeating the same question, check if customer changed their mind or ordered different items!
			msgLower := strings.ToLower(req.MessageText)
			isExplicitChange := strings.Contains(msgLower, "ga jadi") || strings.Contains(msgLower, "gak jadi") ||
				strings.Contains(msgLower, "batal") || strings.Contains(msgLower, "ganti") ||
				strings.Contains(msgLower, "tukar") || strings.Contains(msgLower, "bukan") ||
				strings.Contains(msgLower, "maksudnya") || strings.Contains(msgLower, "tambah")

			hasFoodTerm := strings.Contains(msgLower, "martabak") || strings.Contains(msgLower, "terang bulan") ||
				strings.Contains(msgLower, "terangbulan") || strings.Contains(msgLower, "terbul") ||
				strings.Contains(msgLower, "toping") || strings.Contains(msgLower, "topping") ||
				strings.Contains(msgLower, "besar") || strings.Contains(msgLower, "biasa") ||
				strings.Contains(msgLower, "spesial") || strings.Contains(msgLower, "istimewa") ||
				strings.Contains(msgLower, "sosis") || strings.Contains(msgLower, "jamur") ||
				strings.Contains(msgLower, "ayam") || strings.Contains(msgLower, "sapi") ||
				strings.Contains(msgLower, "keju") || strings.Contains(msgLower, "coklat") ||
				strings.Contains(msgLower, "pizza") || strings.Contains(msgLower, "nasi") ||
				strings.Contains(msgLower, "mie") || strings.Contains(msgLower, "pesan") ||
				strings.Contains(msgLower, "order")

			if isExplicitChange || hasFoodTerm {
				newDraft, run, extractErr := s.ExtractOrder(ctx, ExtractionRequest{
					InboundMessageID: req.InboundMessageID,
					MessageText:      req.MessageText,
					SenderPhone:      req.SenderPhone,
					CustomerName:     state.CustomerName,
					CorrelationID:    correlationID,
					Session:          session,
					PromptContext:    pCtx,
				})
				if extractErr == nil && len(newDraft.Items) > 0 {
					isReplacing := strings.Contains(msgLower, "ga jadi") || strings.Contains(msgLower, "gak jadi") ||
						strings.Contains(msgLower, "batal") || strings.Contains(msgLower, "ganti") ||
						strings.Contains(msgLower, "tukar") || strings.Contains(msgLower, "bukan") ||
						strings.Contains(msgLower, "maksudnya") || !strings.Contains(msgLower, "tambah")

					var mergedDraft *DraftCandidate
					if isReplacing {
						mergedDraft = newDraft
					} else {
						mergedDraft = state.CurrentDraft
						mergedDraft.Items = append(mergedDraft.Items, newDraft.Items...)
						mergedDraft.TotalAmount += newDraft.TotalAmount
						mergedDraft.SubtotalAmount += newDraft.SubtotalAmount
					}

					plan := s.clarifier.PlanClarification(mergedDraft, 0, categories)
					if plan.RequiresClarification {
						state.Status = ConversationAwaitingClarification
						state.CurrentDraft = mergedDraft
						state.PendingAmbiguity = plan.PriorityAmbiguity
						replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
						state.LastQuestion = replyQ
						state.ClarificationAttempts = 0
						_ = s.convStore.Save(ctx, state)

						return &TurnResponse{
							State:            state,
							Draft:            mergedDraft,
							ReplyText:        replyQ,
							RequiresHandoff:  false,
							HandledByAgent:   true,
							AutomationPaused: false,
							Run:              run,
						}, nil
					}

					// Unambiguous and complete!
					state.Status = ConversationReadyForConfirmation
					state.CurrentDraft = mergedDraft
					state.PendingAmbiguity = ""
					state.LastQuestion = ""
					state.ClarificationAttempts = 0
					state.ToolFailureCount = 0
					state.DraftVersion++
					state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
					summaryText := formatOrderSummary(mergedDraft, state.CustomerName)
					state.LastQuestion = summaryText
					_ = s.convStore.Save(ctx, state)

					return &TurnResponse{
						State:            state,
						Draft:            mergedDraft,
						ReplyText:        summaryText,
						RequiresHandoff:  false,
						HandledByAgent:   true,
						AutomationPaused: false,
						Run:              run,
					}, nil
				}
			}

			// Clarification attempt failed - standard retry
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
				replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
				state.LastQuestion = replyQ
				_ = s.convStore.Save(ctx, state)
				s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": HandoffPriorityNormal})

				return &TurnResponse{
					State:            state,
					Draft:            updatedDraft,
					ReplyText:        replyQ,
					RequiresHandoff:  true,
					HandledByAgent:   false,
					AutomationPaused: true,
				}, nil
			}

			replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
			state.LastQuestion = replyQ
			state.PendingAmbiguity = plan.PriorityAmbiguity
			state.CurrentDraft = updatedDraft
			_ = s.convStore.Save(ctx, state)

			return &TurnResponse{
				State:            state,
				Draft:            updatedDraft,
				ReplyText:        replyQ,
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
			replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
			state.LastQuestion = replyQ
			state.ClarificationAttempts = 0 // reset attempts for the new question
			_ = s.convStore.Save(ctx, state)

			return &TurnResponse{
				State:            state,
				Draft:            updatedDraft,
				ReplyText:        replyQ,
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
		summaryText := formatOrderSummary(updatedDraft, state.CustomerName)
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
				greeting := "kak"
				if state.CustomerName != "" {
					greeting = "kak " + state.CustomerName
				}
				replyText := fmt.Sprintf("Mohon maaf %s, terdapat perubahan pada menu: %s.\nTotal pesanan baru menjadi Rp %d.\n\nApakah %s setuju melanjutkan pesanan ini?", greeting, changeReason, updatedDraft.TotalAmount, greeting)
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

			customerDisplayName := "Pelanggan WhatsApp"
			if state.CustomerName != "" {
				customerDisplayName = state.CustomerName
			}
			idempotencyKey := fmt.Sprintf("wa-conf-%s-%d", state.ID, state.DraftVersion)
			if state.ConfirmationToken != "" {
				idempotencyKey = fmt.Sprintf("wa-%s", state.ConfirmationToken)
			}
			createIn := order.WhatsAppOrderCreateInput{
				CustomerPhone: req.SenderPhone,
				CustomerName:  customerDisplayName,
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
					reply := personalizeCustomerGreeting("Mohon maaf kak, sistem kami mengalami kendala teknis saat memproses pesanan kakak. Percakapan ini kami alihkan ke staf kami.", state.CustomerName)
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

			if state.CustomerName != "" && s.customerMemory != nil {
				_, _ = s.customerMemory.UpsertName(ctx, req.SenderPhone, state.CustomerName)
			}

			orderSummary := &WhatsAppOrderSummary{
				ID:                  orderRes.ID,
				OrderNumber:         orderRes.OrderNumber,
				PublicTrackingToken: orderRes.PublicTrackingToken,
				Status:              orderRes.Status,
				TotalAmount:         orderRes.TotalAmount,
				CreatedAt:           orderRes.CreatedAt,
			}

			successReply := FormatOrderSuccessMessage(orderRes.OrderNumber, orderRes.PublicTrackingToken, orderRes.TotalAmount, state.CustomerName)

			var mediaAttachments []MediaAttachment
			var createdOrd order.OrderDetail
			if s.orderReader != nil {
				if fetched, fetchErr := s.orderReader.GetByID(ctx, orderRes.ID); fetchErr == nil && fetched.ID != "" {
					createdOrd = fetched
				}
			}
			if createdOrd.ID == "" {
				createdOrd = order.OrderDetail{
					ID:                  orderRes.ID,
					OrderNumber:         orderRes.OrderNumber,
					PublicTrackingToken: orderRes.PublicTrackingToken,
					Status:              orderRes.Status,
					TotalAmount:         orderRes.TotalAmount,
					CustomerName:        customerDisplayName,
					CreatedAt:           orderRes.CreatedAt,
				}
				if state.CurrentDraft != nil {
					for _, it := range state.CurrentDraft.Items {
						var mods []order.ModifierSnapshot
						for _, m := range it.SelectedModifiers {
							mods = append(mods, order.ModifierSnapshot{Name: m.OptionName})
						}
						createdOrd.Items = append(createdOrd.Items, order.OrderItemDetail{
							Name:            it.Name,
							Quantity:        it.Quantity,
							LineTotalAmount: it.LineTotalAmount,
							Modifiers:       mods,
						})
					}
				}
			}
			if receiptAtt := buildReceiptMediaAttachment(createdOrd, state.CustomerName); receiptAtt != nil {
				mediaAttachments = append(mediaAttachments, *receiptAtt)
			}

			return &TurnResponse{
				State:            state,
				Draft:            state.CurrentDraft,
				ReplyText:        successReply,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
				Order:            orderSummary,
				MediaAttachments: mediaAttachments,
			}, nil

		case IntentCancel:
			state.Status = ConversationCollecting
			state.CurrentDraft = nil
			state.ConfirmationToken = ""
			state.DraftVersion++
			state.PendingAmbiguity = ""
			state.LastQuestion = ""
			_ = s.convStore.Save(ctx, state)

			greeting := "kak"
			if state.CustomerName != "" {
				greeting = "kak " + state.CustomerName
			}
			reply := fmt.Sprintf("Baik %s, draft pesanan telah dibatalkan. Jika ingin memesan kembali di lain waktu, silakan hubungi kami lagi ya!", greeting)
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
				CustomerName:     state.CustomerName,
				CorrelationID:    correlationID,
				Session:          session,
				PromptContext:    pCtx,
			})
			if err != nil || len(newDraft.Items) == 0 {
				greeting := "kak"
				if state.CustomerName != "" {
					greeting = "kak " + state.CustomerName
				}
				reply := fmt.Sprintf("Mohon maaf %s, kami belum menangkap perubahan yang dimaksud. Bisa tolong sebutkan menu yang ingin ditambah/diubah, atau mau tetap lanjut dengan pesanan yang tadi %s?", greeting, greeting)
				return &TurnResponse{
					State:            state,
					Draft:            state.CurrentDraft,
					ReplyText:        reply,
					RequiresHandoff:  false,
					HandledByAgent:   true,
					AutomationPaused: false,
				}, nil
			}

			// Check if customer wants to ADD (tambah) or REPLACE (ganti/ga jadi)
			msgLower := strings.ToLower(req.MessageText)
			isAdd := strings.Contains(msgLower, "tambah") || strings.Contains(msgLower, "plus") ||
				strings.Contains(msgLower, "sama") || strings.Contains(msgLower, "dan") ||
				strings.Contains(msgLower, "sekalian") || strings.Contains(msgLower, "juga")

			var finalDraft *DraftCandidate
			if isAdd && state.CurrentDraft != nil && len(state.CurrentDraft.Items) > 0 {
				finalDraft = state.CurrentDraft
				finalDraft.Items = append(finalDraft.Items, newDraft.Items...)
				if newDraft.Notes != "" {
					if finalDraft.Notes != "" {
						finalDraft.Notes += "; " + newDraft.Notes
					} else {
						finalDraft.Notes = newDraft.Notes
					}
				}
				recalculateTotals(finalDraft)
			} else {
				finalDraft = newDraft
			}

			plan := s.clarifier.PlanClarification(finalDraft, 0, categories)
			if plan.RequiresClarification {
				state.Status = ConversationAwaitingClarification
				state.CurrentDraft = finalDraft
				state.PendingAmbiguity = plan.PriorityAmbiguity
				clarifyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
				state.LastQuestion = clarifyQ
				state.ClarificationAttempts = 0
				state.DraftVersion++
				_ = s.convStore.Save(ctx, state)

				return &TurnResponse{
					State:            state,
					Draft:            finalDraft,
					ReplyText:        clarifyQ,
					RequiresHandoff:  false,
					HandledByAgent:   true,
					AutomationPaused: false,
					Run:              run,
				}, nil
			}

			state.Status = ConversationReadyForConfirmation
			state.CurrentDraft = finalDraft
			state.PendingAmbiguity = ""
			state.ClarificationAttempts = 0
			state.DraftVersion++
			state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
			summaryText := formatOrderSummary(finalDraft, state.CustomerName)
			state.LastQuestion = summaryText
			_ = s.convStore.Save(ctx, state)

			return &TurnResponse{
				State:            state,
				Draft:            finalDraft,
				ReplyText:        summaryText,
				RequiresHandoff:  false,
				HandledByAgent:   true,
				AutomationPaused: false,
				Run:              run,
			}, nil

		case IntentUnknown:
			if DetectOrderStatusInquiry(req.MessageText) {
				reply := formatDraftStatusMessage(state.CurrentDraft, state.CustomerName)
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
			if isInfo, infoType := DetectStoreInfoInquiry(req.MessageText); isInfo {
				infoReply := formatStoreInfoMessage(infoType, state.CustomerName)
				greeting := "kak"
				if state.CustomerName != "" {
					greeting = "kak " + state.CustomerName
				}
				reply := fmt.Sprintf("%s\n\nApakah pesanan yang tadi mau langsung kami buatkan ya %s?", infoReply, greeting)
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
			greeting := "kak"
			if state.CustomerName != "" {
				greeting = "kak " + state.CustomerName
			}
			reply := fmt.Sprintf("Pesanan belum terkonfirmasi nih %s. Apakah pesanannya mau langsung kami buatkan? Atau ada menu lain yang ingin ditambahkan atau diubah terlebih dahulu ya %s?", greeting, greeting)
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
			reply := "Sama-sama kak! Pesanan kakak sedang kami siapkan ya."
			if state.CustomerName != "" {
				reply = fmt.Sprintf("Sama-sama kak %s! Pesanan kakak sedang kami siapkan ya.", state.CustomerName)
			}
			return &TurnResponse{
				State:            state,
				ReplyText:        reply,
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
		state.DraftVersion++
	}

	// 6. Initial message / Collecting state
	draft, run, err := s.ExtractOrder(ctx, ExtractionRequest{
		InboundMessageID: req.InboundMessageID,
		MessageText:      req.MessageText,
		SenderPhone:      req.SenderPhone,
		CustomerName:     state.CustomerName,
		CorrelationID:    correlationID,
		Session:          session,
		PromptContext:    pCtx,
	})
	if err != nil {
		state.ToolFailureCount++
		if state.ToolFailureCount >= MaxToolFailures {
			state.Status = ConversationHandoff
			state.HandoffStatus = HandoffStatusPending
			reason := "repeated_tool_failure"
			state.HandoffReason = &reason
			state.HandoffPriority = HandoffPriorityHigh
			reply := personalizeCustomerGreeting("Mohon maaf kak, sistem kami sedang mengalami gangguan teknis saat memproses pesanan. Percakapan ini kami alihkan ke staf kami.", state.CustomerName)
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

	// Conversational / Question / Greeting (empty items)
	if len(draft.Items) == 0 {
		reply := draft.ReplyText
		var mediaAttachments []MediaAttachment

		if reply == "" {
			reply, mediaAttachments = s.fallbackConversationalReply(ctx, req, state, categories)
		} else if DetectCatalogInquiry(req.MessageText) {
			mediaAttachments = getCatalogMediaAttachments()
		}

		state.Status = ConversationAwaitingClarification
		state.PendingAmbiguity = "empty_order_items"
		if state.CurrentDraft == nil {
			state.CurrentDraft = &DraftCandidate{
				CustomerPhone: req.SenderPhone,
				CustomerName:  state.CustomerName,
				Items:         []ExtractedItem{},
			}
		}
		state.LastQuestion = reply
		state.ClarificationAttempts = 0
		_ = s.convStore.Save(ctx, state)

		return &TurnResponse{
			State:            state,
			Draft:            state.CurrentDraft,
			ReplyText:        reply,
			RequiresHandoff:  false,
			HandledByAgent:   true,
			AutomationPaused: false,
			Run:              run,
			MediaAttachments: mediaAttachments,
		}, nil
	}

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
		replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
		state.LastQuestion = replyQ
		_ = s.convStore.Save(ctx, state)
		s.recordHandoffAudit(ctx, state, HandoffActionTriggered, "SYSTEM", "SYSTEM", reason, correlationID, map[string]any{"priority": HandoffPriorityNormal})

		return &TurnResponse{
			State:            state,
			Draft:            draft,
			ReplyText:        replyQ,
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
		replyQ := personalizeCustomerGreeting(plan.QuestionText, state.CustomerName)
		state.LastQuestion = replyQ
		state.ClarificationAttempts = 0
		_ = s.convStore.Save(ctx, state)

		return &TurnResponse{
			State:            state,
			Draft:            draft,
			ReplyText:        replyQ,
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
	if state.DraftVersion < 1 {
		state.DraftVersion = 1
	} else {
		state.DraftVersion++
	}
	state.ConfirmationToken = fmt.Sprintf("tok-%s-%d", newID(), state.DraftVersion)
	summaryText := formatOrderSummary(draft, state.CustomerName)
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

func formatOrderSummary(draft *DraftCandidate, customerName string) string {
	var sb strings.Builder
	customerName = strings.TrimSpace(customerName)
	if customerName != "" {
		sb.WriteString(fmt.Sprintf("Baik kak %s, berikut ringkasan pesanan kak:\n", customerName))
	} else {
		sb.WriteString("Berikut ringkasan pesanan kak:\n")
	}
	for _, it := range draft.Items {
		var modNames []string
		for _, m := range it.SelectedModifiers {
			if strings.EqualFold(m.OptionName, "Original") && m.PriceDeltaAmount == 0 {
				continue
			}
			modNames = append(modNames, m.OptionName)
		}
		modStr := ""
		if len(modNames) > 0 {
			modStr = fmt.Sprintf(" (%s)", strings.Join(modNames, ", "))
		}
		sb.WriteString(fmt.Sprintf("- %dx %s%s: Rp %d\n", it.Quantity, it.Name, modStr, it.LineTotalAmount))
	}
	sb.WriteString(fmt.Sprintf("\nTotal: Rp %d\n", draft.SubtotalAmount))
	fulfillment := draft.FulfillmentType
	if fulfillment == "" || fulfillment == "PICKUP" {
		fulfillment = "PICKUP (Bawa Pulang)"
	} else if fulfillment == "DINE_IN" {
		fulfillment = "DINE IN (Makan di Tempat)"
	}
	sb.WriteString(fmt.Sprintf("Pengambilan: %s\n", fulfillment))
	sb.WriteString("Pembayaran: Tunai / QRIS saat pengambilan di kasir\n")
	if customerName != "" {
		sb.WriteString(fmt.Sprintf("\nApakah pesanannya sudah sesuai kak %s? Kalau sudah oke, langsung kami buatkan ya! 😊", customerName))
	} else {
		sb.WriteString("\nApakah pesanan sudah sesuai kak? Kalau sudah oke, langsung kami buatkan ya! 😊")
	}
	return sb.String()
}

func cleanCustomerName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return ""
	}
	if strings.HasPrefix(name, "+") || strings.HasPrefix(name, "08") || strings.HasPrefix(name, "628") {
		return ""
	}
	hasLetter := false
	for _, r := range name {
		if unicode.IsLetter(r) {
			hasLetter = true
			break
		}
	}
	if !hasLetter {
		return ""
	}
	return name
}

func personalizeCustomerGreeting(text, customerName string) string {
	customerName = strings.TrimSpace(customerName)
	if customerName == "" {
		return text
	}
	if strings.Contains(strings.ToLower(text), strings.ToLower(customerName)) {
		return text
	}
	if strings.HasPrefix(text, "Halo kak!") {
		return strings.Replace(text, "Halo kak!", fmt.Sprintf("Halo kak %s!", customerName), 1)
	}
	if strings.HasPrefix(text, "Halo kak,") {
		return strings.Replace(text, "Halo kak,", fmt.Sprintf("Halo kak %s,", customerName), 1)
	}
	if strings.HasPrefix(text, "Mohon maaf kak,") {
		return strings.Replace(text, "Mohon maaf kak,", fmt.Sprintf("Mohon maaf kak %s,", customerName), 1)
	}
	if strings.HasPrefix(text, "Baik kak,") {
		return strings.Replace(text, "Baik kak,", fmt.Sprintf("Baik kak %s,", customerName), 1)
	}
	return text
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

func findAssetPath(relative string) string {
	candidates := []string{
		relative,
		"web/" + relative,
		"../web/" + relative,
		"../../web/" + relative,
		"/app/" + relative,
		"/app/web/" + relative,
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return relative
}

func getCatalogMediaAttachments() []MediaAttachment {
	attachments := make([]MediaAttachment, 0, 2)
	martelPath := findAssetPath("assets/menu-martabak-telur.jpg")
	if data, err := os.ReadFile(martelPath); err == nil && len(data) > 0 {
		attachments = append(attachments, MediaAttachment{
			Type:     "image",
			Filename: "menu-martabak-telur.jpg",
			Caption:  "🥞 *Menu Martabak Telur Spesial Jenggirat Kediri*\nPilihan isian Daging Sapi, Daging Ayam, Sosis/Jamur, dan Martel Mozarella lezat!",
			Data:     data,
			FilePath: martelPath,
		})
	}

	terbulPath := findAssetPath("assets/menu-terang-bulan.png")
	if data, err := os.ReadFile(terbulPath); err == nil && len(data) > 0 {
		attachments = append(attachments, MediaAttachment{
			Type:     "image",
			Filename: "menu-terang-bulan.png",
			Caption:  "✨ *Menu Terang Bulan Manis Jenggirat Kediri*\nManis susu kenyal sampai pagi dengan aneka pilihan toping & base cake spesial!",
			Data:     data,
			FilePath: terbulPath,
		})
	}
	return attachments
}

func buildReceiptMediaAttachment(ord order.OrderDetail, customerName string) *MediaAttachment {
	var items []receipt.ReceiptItem
	for _, it := range ord.Items {
		var modNames []string
		for _, m := range it.Modifiers {
			modNames = append(modNames, m.Name)
		}
		items = append(items, receipt.ReceiptItem{
			Name:            it.Name,
			Modifiers:       modNames,
			Quantity:        it.Quantity,
			UnitPriceAmount: it.UnitPriceAmount,
			LineTotalAmount: it.LineTotalAmount,
		})
	}

	phoneStr := ""
	if ord.CustomerPhone != nil {
		phoneStr = *ord.CustomerPhone
	}
	dispName := ord.CustomerName
	if dispName == "" {
		dispName = customerName
	}

	pdfBytes, err := receipt.GenerateReceiptPDF(receipt.ReceiptData{
		OrderNumber:         ord.OrderNumber,
		StoreName:           "Martabak & Terang Bulan Jenggirat Kediri",
		StoreAddress:        "Timur Gg. Ketoprak Katang, Kediri",
		StorePhone:          "0822 4350 9775",
		CustomerName:        dispName,
		CustomerPhone:       phoneStr,
		OrderDate:           ord.CreatedAt,
		FulfillmentType:     "Takeaway (Pickup)",
		Status:              ord.Status,
		Items:               items,
		SubtotalAmount:      ord.SubtotalAmount,
		DiscountAmount:      ord.DiscountAmount,
		DiscountName:        ord.DiscountName,
		TotalAmount:         ord.TotalAmount,
		PaymentMethod:       "Tunai / QRIS Kasir",
		PublicTrackingToken: ord.PublicTrackingToken,
	})
	if err != nil {
		return nil
	}

	return &MediaAttachment{
		Type:     "document",
		Filename: fmt.Sprintf("struk-%s.pdf", ord.OrderNumber),
		Caption:  fmt.Sprintf("🧾 Struk Resmi Pesanan #%s - Martabak & Terang Bulan Jenggirat Kediri", ord.OrderNumber),
		Data:     pdfBytes,
	}
}

func formatDraftStatusMessage(draft *DraftCandidate, customerName string) string {
	var sb strings.Builder
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}
	sb.WriteString(fmt.Sprintf("Halo %s! Berikut draf pesanan kakak saat ini yang belum dikonfirmasi:\n", greeting))
	for _, it := range draft.Items {
		var modNames []string
		for _, m := range it.SelectedModifiers {
			if strings.EqualFold(m.OptionName, "Original") && m.PriceDeltaAmount == 0 {
				continue
			}
			modNames = append(modNames, m.OptionName)
		}
		modStr := ""
		if len(modNames) > 0 {
			modStr = fmt.Sprintf(" (%s)", strings.Join(modNames, ", "))
		}
		sb.WriteString(fmt.Sprintf("- %dx %s%s: Rp %d\n", it.Quantity, it.Name, modStr, it.LineTotalAmount))
	}
	sb.WriteString(fmt.Sprintf("\nTotal: Rp %d\n", draft.SubtotalAmount))
	sb.WriteString(fmt.Sprintf("Apakah pesanannya mau langsung kami buatkan atau ada tambahan menu lain %s? 😊", greeting))
	return sb.String()
}

func (s *Service) buildPromptContext(ctx context.Context, req TurnRequest, state *ConversationState) PromptContext {
	customerName := state.CustomerName
	if customerName == "" {
		customerName = cleanCustomerName(req.CustomerName)
	}

	var activeOrderStatus string
	var activeOrderItems string
	var activeOrder *order.OrderDetail
	if state.LastOrderID != nil && *state.LastOrderID != "" && s.orderReader != nil {
		if ord, err := s.orderReader.GetByID(ctx, *state.LastOrderID); err == nil && ord.ID != "" {
			activeOrder = &ord
		}
	}
	if activeOrder == nil && s.orderReader != nil {
		if ord, err := s.orderReader.GetLatestByPhone(ctx, req.SenderPhone); err == nil && ord.ID != "" {
			activeOrder = &ord
		}
	}

	if activeOrder != nil {
		statusLabel := activeOrder.Status
		switch activeOrder.Status {
		case "PENDING", "SUBMITTED":
			statusLabel = "Menunggu Konfirmasi Kasir"
		case "ACCEPTED", "CONFIRMED":
			statusLabel = "Dikonfirmasi Kasir"
		case "PREPARING":
			statusLabel = "Sedang Dimasak / Disiapkan di Dapur"
		case "READY", "READY_FOR_PICKUP":
			statusLabel = "Sudah Matang & Siap Diambil di Kasir"
		case "COMPLETED":
			statusLabel = "Selesai / Sudah Diambil"
		case "CANCELLED":
			statusLabel = "Dibatalkan"
		}
		activeOrderStatus = fmt.Sprintf("Pesanan #%s - Status: %s (%s). Total: Rp %d.", activeOrder.OrderNumber, activeOrder.Status, statusLabel, activeOrder.TotalAmount)
		if activeOrder.PublicTrackingToken != "" {
			activeOrderStatus += fmt.Sprintf(" Link tracking: http://localhost:3000/orders/track/%s", activeOrder.PublicTrackingToken)
		}

		var itemNames []string
		for _, it := range activeOrder.Items {
			itemNames = append(itemNames, fmt.Sprintf("%dx %s", it.Quantity, it.Name))
		}
		if len(itemNames) > 0 {
			activeOrderItems = strings.Join(itemNames, ", ")
		}
	}

	var currentDraftInfo string
	if state.CurrentDraft != nil && len(state.CurrentDraft.Items) > 0 {
		var draftItems []string
		for _, it := range state.CurrentDraft.Items {
			var mods []string
			for _, m := range it.SelectedModifiers {
				if !strings.EqualFold(m.OptionName, "Original") || m.PriceDeltaAmount > 0 {
					mods = append(mods, m.OptionName)
				}
			}
			modStr := ""
			if len(mods) > 0 {
				modStr = fmt.Sprintf(" (%s)", strings.Join(mods, ", "))
			}
			draftItems = append(draftItems, fmt.Sprintf("%dx %s%s (Rp %d)", it.Quantity, it.Name, modStr, it.LineTotalAmount))
		}
		currentDraftInfo = fmt.Sprintf("Draf pesanan belum terkonfirmasi: %s. Subtotal: Rp %d.", strings.Join(draftItems, ", "), state.CurrentDraft.SubtotalAmount)
	}

	outletInfo := "Nama: Martabak & Terang Bulan Jenggirat. Alamat: Jl. Ahmad Yani No. 45 (Kediri / Banyuwangi). Jam Buka: 16:00 - 23:00 WIB setiap hari. Pesanan bisa diambil langsung di outlet (Pickup / Takeaway) atau pesan lewat WhatsApp."

	return PromptContext{
		CustomerName:      customerName,
		ActiveOrderStatus: activeOrderStatus,
		ActiveOrderItems:  activeOrderItems,
		CurrentDraftInfo:  currentDraftInfo,
		OutletInfo:        outletInfo,
	}
}

func (s *Service) fallbackConversationalReply(ctx context.Context, req TurnRequest, state *ConversationState, categories []catalog.Category) (string, []MediaAttachment) {
	var activeOrder *order.OrderDetail
	if state.LastOrderID != nil && *state.LastOrderID != "" && s.orderReader != nil {
		if ord, err := s.orderReader.GetByID(ctx, *state.LastOrderID); err == nil && ord.ID != "" {
			activeOrder = &ord
		}
	}
	if activeOrder == nil && s.orderReader != nil {
		if ord, err := s.orderReader.GetLatestByPhone(ctx, req.SenderPhone); err == nil && ord.ID != "" {
			activeOrder = &ord
		}
	}

	if DetectOrderStatusInquiry(req.MessageText) {
		if state.CurrentDraft != nil && len(state.CurrentDraft.Items) > 0 {
			return formatDraftStatusMessage(state.CurrentDraft, state.CustomerName), nil
		}
		if activeOrder != nil {
			return formatOrderStatusMessage(*activeOrder, state.CustomerName), nil
		}
		return formatNoActiveOrderMessage(state.CustomerName), nil
	}

	if isCat, catType := DetectCategoryInquiry(req.MessageText); isCat {
		return formatCategoryInquiryMessage(catType, state.CustomerName), nil
	}

	if DetectCatalogInquiry(req.MessageText) {
		reply := formatCatalogMenuMessage(categories, state.CustomerName)
		if state.CurrentDraft != nil && len(state.CurrentDraft.Items) > 0 {
			reply += "\n\n📌 _Catatan: Draf pesanan kakak sebelumnya masih tersimpan. Setelah melihat foto/menu, mau lanjut dibuatkan atau ada yang mau diubah kak?_"
		}
		return reply, getCatalogMediaAttachments()
	}

	if DetectRecommendationInquiry(req.MessageText) {
		return formatRecommendationMessage(state.CustomerName), nil
	}

	if isInfo, infoType := DetectStoreInfoInquiry(req.MessageText); isInfo {
		return formatStoreInfoMessage(infoType, state.CustomerName), nil
	}

	return formatGreetingMessage(state.CustomerName), nil
}
