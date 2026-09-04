package hermes

import (
	"testing"
)

func TestConfidenceEvaluator_HighConfidence(t *testing.T) {
	eval := NewConfidenceEvaluator(0.75)

	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{MenuName: "Nasi Goreng Spesial", Quantity: 1, Confidence: 0.95},
		},
		Confidence: 0.95,
	}

	resolveResult := &ResolveResult{
		Items: []ExtractedItem{
			{Name: "Nasi Goreng Spesial", Quantity: 1, Confidence: 0.95},
		},
		IsAmbiguous: false,
	}

	score, isAmbiguous, reasons := eval.Evaluate(raw, resolveResult)
	if isAmbiguous {
		t.Fatalf("expected not ambiguous, got reasons: %v", reasons)
	}
	if score < 0.75 {
		t.Fatalf("expected score >= 0.75, got %.2f", score)
	}
	if len(reasons) > 0 {
		t.Errorf("expected 0 reasons, got %v", reasons)
	}
}

func TestConfidenceEvaluator_LowScoreTrigger(t *testing.T) {
	eval := NewConfidenceEvaluator(0.75)

	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{MenuName: "Nasi Goreng", Quantity: 1, Confidence: 0.50},
		},
		Confidence: 0.60,
	}

	resolveResult := &ResolveResult{
		Items: []ExtractedItem{
			{Name: "Nasi Goreng", Quantity: 1, Confidence: 0.50},
		},
		IsAmbiguous: false,
	}

	score, isAmbiguous, reasons := eval.Evaluate(raw, resolveResult)
	if !isAmbiguous {
		t.Fatalf("expected isAmbiguous = true for score %.2f < 0.75", score)
	}

	foundReason := false
	for _, r := range reasons {
		if r == "low_item_confidence:Nasi Goreng:0.50" {
			foundReason = true
			break
		}
	}
	if !foundReason {
		t.Errorf("expected 'low_item_confidence:Nasi Goreng:0.50' in reasons, got %v", reasons)
	}
}

func TestConfidenceEvaluator_UncertaintyKeyword(t *testing.T) {
	eval := NewConfidenceEvaluator(0.75)

	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{MenuName: "Nasi Goreng", Quantity: 1, Notes: "kalau ada telur ya", Confidence: 0.85},
		},
		Confidence: 0.85,
	}

	resolveResult := &ResolveResult{
		Items: []ExtractedItem{
			{Name: "Nasi Goreng", Quantity: 1, Confidence: 0.85},
		},
		IsAmbiguous: false,
	}

	score, isAmbiguous, reasons := eval.Evaluate(raw, resolveResult)
	if !isAmbiguous {
		t.Fatalf("expected isAmbiguous = true due to uncertainty keyword")
	}

	foundReason := false
	for _, r := range reasons {
		if r == "uncertainty_detected:kalau ada" {
			foundReason = true
			break
		}
	}
	if !foundReason {
		t.Errorf("expected uncertainty_detected:kalau ada, got %v (score=%.2f)", reasons, score)
	}
}

func TestConfidenceEvaluator_EmptyItems(t *testing.T) {
	eval := NewConfidenceEvaluator(0.75)

	raw := &RawExtractedOrder{
		Items:      []RawExtractedItem{},
		Confidence: 0.20,
	}

	resolveResult := &ResolveResult{
		Items:            []ExtractedItem{},
		IsAmbiguous:      true,
		AmbiguityReasons: []string{"empty_order_items"},
	}

	score, isAmbiguous, reasons := eval.Evaluate(raw, resolveResult)
	if !isAmbiguous {
		t.Fatalf("expected ambiguous for empty items")
	}
	if score != 0.0 {
		t.Errorf("expected score 0.0, got %.2f", score)
	}
	if len(reasons) == 0 {
		t.Errorf("expected reasons, got empty")
	}
}
