package hermes

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// Service coordinates LLM extraction, catalog resolution, confidence policy, and audit logging.
type Service struct {
	client        LLMClient
	resolver      *CatalogResolver
	evaluator     *ConfidenceEvaluator
	store         RunStore
	modelName     string
	promptVersion string
}

// Config holds configuration options for Hermes Service.
type Config struct {
	Client              LLMClient
	CatalogProvider     CatalogProvider
	Store               RunStore
	ModelName           string
	PromptVersion       string
	ConfidenceThreshold float64
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

	return &Service{
		client:        cfg.Client,
		resolver:      resolver,
		evaluator:     evaluator,
		store:         cfg.Store,
		modelName:     modelName,
		promptVersion: promptVer,
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
