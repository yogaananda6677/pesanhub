package hermes

import (
	"context"
	"testing"
)

func TestDraftMerger_PartialModifierUpdate(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	merger := NewDraftMerger(provider)
	cats := sampleCatalog()

	// Initial draft has Nasi Goreng Spesial with missing Level Pedas
	initialDraft := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:               "menu-nasgor",
				SKU:                  "NASGOR",
				Name:                 "Nasi Goreng Spesial",
				Quantity:             2,
				UnitPriceAmount:      20000,
				ModifiersTotalAmount: 0,
				LineTotalAmount:      40000,
				SelectedModifiers:    []SelectedModifier{},
				Notes:                "jangan pakai timun",
			},
			{
				MenuID:          "menu-esteh",
				SKU:             "ESTEH",
				Name:            "Es Teh Manis",
				Quantity:        2,
				UnitPriceAmount: 5000,
				LineTotalAmount: 10000,
			},
		},
		FulfillmentType:  "PICKUP",
		PaymentMethod:    "QRIS",
		SubtotalAmount:   50000,
		TotalAmount:      50000,
		AmbiguityReasons: []string{"missing_required_modifier:Level Pedas"},
		IsAmbiguous:      true,
	}

	// Customer answers "Pedas"
	updatedDraft, resolved, err := merger.MergeClarification(
		context.Background(),
		initialDraft,
		"missing_required_modifier:Level Pedas",
		"pedas",
		cats,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !resolved {
		t.Fatalf("expected resolved = true for matching modifier")
	}

	// Ambiguity should now be cleared!
	if updatedDraft.IsAmbiguous {
		t.Fatalf("expected draft to become unambiguous, got reasons: %v", updatedDraft.AmbiguityReasons)
	}
	if len(updatedDraft.AmbiguityReasons) != 0 {
		t.Errorf("expected 0 ambiguity reasons, got %v", updatedDraft.AmbiguityReasons)
	}

	// Existing notes, quantity, and second item MUST be preserved!
	if len(updatedDraft.Items) != 2 {
		t.Fatalf("expected 2 items preserved, got %d", len(updatedDraft.Items))
	}
	nasgor := updatedDraft.Items[0]
	if nasgor.Notes != "jangan pakai timun" {
		t.Errorf("expected notes preserved, got %q", nasgor.Notes)
	}
	if nasgor.Quantity != 2 {
		t.Errorf("expected quantity preserved as 2, got %d", nasgor.Quantity)
	}
	if len(nasgor.SelectedModifiers) != 1 || nasgor.SelectedModifiers[0].OptionName != "Pedas" {
		t.Errorf("expected SelectedModifiers to contain Pedas, got %v", nasgor.SelectedModifiers)
	}
	// Second item preserved
	esteh := updatedDraft.Items[1]
	if esteh.Name != "Es Teh Manis" || esteh.Quantity != 2 {
		t.Errorf("expected second item preserved, got %+v", esteh)
	}
}

func TestDraftMerger_FulfillmentAndPayment(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	merger := NewDraftMerger(provider)
	cats := sampleCatalog()

	draft := &DraftCandidate{
		Items: []ExtractedItem{
			{Name: "Nasi Goreng Spesial", MenuID: "menu-nasgor", Quantity: 1, LineTotalAmount: 20000},
		},
		AmbiguityReasons: []string{"missing_fulfillment_type"},
		IsAmbiguous:      true,
	}

	// Answer takeaway
	d1, res1, err := merger.MergeClarification(context.Background(), draft, "missing_fulfillment_type", "bungkus takeaway", cats)
	if err != nil || !res1 {
		t.Fatalf("failed to merge fulfillment: %v, res=%v", err, res1)
	}
	if d1.FulfillmentType != "PICKUP" {
		t.Errorf("expected PICKUP, got %s", d1.FulfillmentType)
	}

	// Answer QRIS for payment
	d1.AmbiguityReasons = []string{"missing_payment_method"}
	d2, res2, err := merger.MergeClarification(context.Background(), d1, "missing_payment_method", "mau bayar pakai qris aja", cats)
	if err != nil || !res2 {
		t.Fatalf("failed to merge payment: %v, res=%v", err, res2)
	}
	if d2.PaymentMethod != "QRIS" {
		t.Errorf("expected QRIS, got %s", d2.PaymentMethod)
	}
}

func TestDraftMerger_QuantityClarification(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	merger := NewDraftMerger(provider)
	cats := sampleCatalog()

	draft := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "menu-nasgor",
				Name:            "Nasi Goreng Spesial",
				Quantity:        0,
				UnitPriceAmount: 20000,
				LineTotalAmount: 0,
			},
		},
		AmbiguityReasons: []string{"invalid_quantity:Nasi Goreng Spesial"},
		IsAmbiguous:      true,
	}

	updated, res, err := merger.MergeClarification(context.Background(), draft, "invalid_quantity:Nasi Goreng Spesial", "3 porsi ya", cats)
	if err != nil || !res {
		t.Fatalf("failed to merge quantity: %v, res=%v", err, res)
	}

	if updated.Items[0].Quantity != 3 {
		t.Errorf("expected quantity 3, got %d", updated.Items[0].Quantity)
	}
	if updated.Items[0].LineTotalAmount != 60000 {
		t.Errorf("expected line total 60000, got %d", updated.Items[0].LineTotalAmount)
	}
	if updated.SubtotalAmount != 60000 {
		t.Errorf("expected subtotal 60000, got %d", updated.SubtotalAmount)
	}
}

func TestDraftMerger_RevalidateAgainstCatalog_ItemBecomesUnavailable(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	merger := NewDraftMerger(provider)

	// In the initial state, Nasi Goreng is available
	draft := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "menu-nasgor",
				Name:            "Nasi Goreng Spesial",
				Quantity:        1,
				UnitPriceAmount: 20000,
				LineTotalAmount: 20000,
			},
		},
		FulfillmentType:  "PICKUP",
		PaymentMethod:    "QRIS",
		AmbiguityReasons: []string{"missing_fulfillment_type"},
		IsAmbiguous:      true,
	}

	// Now simulate that catalog changed: Nasi Goreng is now marked unavailable (out of stock)
	updatedCatalog := sampleCatalog()
	updatedCatalog[0].Menus[0].Available = false // Nasi Goreng unavailable

	updatedDraft, _, err := merger.MergeClarification(
		context.Background(),
		draft,
		"missing_fulfillment_type",
		"pickup",
		updatedCatalog,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Because Nasi Goreng became unavailable in catalog, revalidation MUST flag menu_unavailable!
	if !updatedDraft.IsAmbiguous {
		t.Fatalf("expected draft to remain ambiguous due to catalog menu unavailability")
	}

	foundReason := false
	for _, r := range updatedDraft.AmbiguityReasons {
		if r == "menu_unavailable:Nasi Goreng Spesial" {
			foundReason = true
			break
		}
	}
	if !foundReason {
		t.Errorf("expected 'menu_unavailable:Nasi Goreng Spesial' in reasons, got %v", updatedDraft.AmbiguityReasons)
	}
}
