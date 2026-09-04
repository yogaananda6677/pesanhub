package hermes

import (
	"strings"
	"testing"
)

func TestClarificationEngine_PriorityHierarchy(t *testing.T) {
	engine := NewClarificationEngine(3)
	cats := sampleCatalog()

	// Draft with menu_unavailable, missing_required_modifier, and missing_fulfillment_type
	draft := &DraftCandidate{
		Items: []ExtractedItem{
			{Name: "Nasi Goreng Spesial", MenuID: "menu-nasgor", Quantity: 1},
		},
		AmbiguityReasons: []string{
			"missing_fulfillment_type",
			"missing_required_modifier:Level Pedas",
			"menu_unavailable:Mie Goreng Jawa",
		},
		IsAmbiguous: true,
	}

	// 1. Should prioritize menu_unavailable first
	plan1 := engine.PlanClarification(draft, 0, cats)
	if plan1.PriorityAmbiguity != "menu_unavailable:Mie Goreng Jawa" {
		t.Fatalf("expected menu_unavailable as top priority, got %s", plan1.PriorityAmbiguity)
	}
	if !strings.Contains(plan1.QuestionText, "Mie Goreng Jawa saat ini sedang habis") {
		t.Errorf("unexpected question text: %s", plan1.QuestionText)
	}

	// 2. Once menu_unavailable is resolved, next priority should be missing_required_modifier
	draft.AmbiguityReasons = []string{
		"missing_fulfillment_type",
		"missing_required_modifier:Level Pedas",
	}
	plan2 := engine.PlanClarification(draft, 0, cats)
	if plan2.PriorityAmbiguity != "missing_required_modifier:Level Pedas" {
		t.Fatalf("expected missing_required_modifier, got %s", plan2.PriorityAmbiguity)
	}
	if !strings.Contains(plan2.QuestionText, "Level Pedas") || !strings.Contains(plan2.QuestionText, "Nasi Goreng Spesial") {
		t.Errorf("question text should mention menu and modifier group, got %s", plan2.QuestionText)
	}
	if len(plan2.Options) == 0 {
		t.Errorf("expected options to be extracted from catalog, got empty")
	}

	// 3. Once modifier is resolved, next should be fulfillment type
	draft.AmbiguityReasons = []string{}
	draft.IsAmbiguous = false
	draft.FulfillmentType = ""
	plan3 := engine.PlanClarification(draft, 0, cats)
	if plan3.PriorityAmbiguity != "missing_fulfillment_type" {
		t.Fatalf("expected missing_fulfillment_type, got %s", plan3.PriorityAmbiguity)
	}
	if !strings.Contains(plan3.QuestionText, "Takeaway/Pickup") {
		t.Errorf("question text should ask fulfillment, got %s", plan3.QuestionText)
	}
}

func TestClarificationEngine_BoundedRetryHandoff(t *testing.T) {
	engine := NewClarificationEngine(3)
	cats := sampleCatalog()

	draft := &DraftCandidate{
		Items:            []ExtractedItem{},
		AmbiguityReasons: []string{"no_valid_items_resolved"},
		IsAmbiguous:      true,
	}

	// Turn 0: ask clarification
	p0 := engine.PlanClarification(draft, 0, cats)
	if p0.RequiresHandoff {
		t.Fatalf("attempt 0 should not trigger handoff")
	}

	// Turn 2: still within limits
	p2 := engine.PlanClarification(draft, 2, cats)
	if p2.RequiresHandoff {
		t.Fatalf("attempt 2 should not trigger handoff")
	}

	// Turn 3 (>= MaxAttempts 3): Must trigger handoff
	p3 := engine.PlanClarification(draft, 3, cats)
	if !p3.RequiresHandoff {
		t.Fatalf("expected handoff triggered at max attempts, got false")
	}
	if p3.HandoffReason != "max_clarification_attempts_exceeded" {
		t.Errorf("expected max_clarification_attempts_exceeded, got %s", p3.HandoffReason)
	}
	if !strings.Contains(p3.QuestionText, "staf kami") {
		t.Errorf("expected handoff message to mention staf, got %s", p3.QuestionText)
	}
}

func TestClarificationEngine_PromptInjectionHandoff(t *testing.T) {
	engine := NewClarificationEngine(3)
	cats := sampleCatalog()

	draft := &DraftCandidate{
		AmbiguityReasons: []string{"prompt_injection_detected:ignore previous instructions"},
		IsAmbiguous:      true,
	}

	plan := engine.PlanClarification(draft, 0, cats)
	if !plan.RequiresHandoff {
		t.Fatalf("expected handoff on prompt injection, got false")
	}
	if plan.HandoffReason != "prompt_injection_detected" {
		t.Errorf("expected prompt_injection_detected, got %s", plan.HandoffReason)
	}
}

func TestClarificationEngine_UnambiguousComplete(t *testing.T) {
	engine := NewClarificationEngine(3)
	cats := sampleCatalog()

	draft := &DraftCandidate{
		Items: []ExtractedItem{
			{Name: "Nasi Goreng Spesial", Quantity: 1, LineTotalAmount: 20000},
		},
		FulfillmentType:   "PICKUP",
		PaymentMethod:     "QRIS",
		OverallConfidence: 0.95,
		IsAmbiguous:       false,
	}

	plan := engine.PlanClarification(draft, 0, cats)
	if plan.RequiresClarification {
		t.Fatalf("expected no clarification needed for complete draft")
	}
	if plan.RequiresHandoff {
		t.Fatalf("expected no handoff needed for complete draft")
	}
}
