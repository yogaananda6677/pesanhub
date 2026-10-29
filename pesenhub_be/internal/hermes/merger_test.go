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

func TestDraftMerger_UnrecognizedModifier_NoCoklatCollision(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	merger := NewDraftMerger(provider)
	cats := sampleCatalog()

	draft := &DraftCandidate{
		Items: []ExtractedItem{
			{Name: "1 Toping - Biasa", MenuID: "menu-tb", Quantity: 1, LineTotalAmount: 18000},
		},
		AmbiguityReasons: []string{"unrecognized_modifier:2 Toping - Biasa"},
		IsAmbiguous:      true,
	}

	// Customer answers "1 topping besar aja rasa coklat" - contains "coklat" which has "ok" substring
	_, resolved, err := merger.MergeClarification(
		context.Background(),
		draft,
		"unrecognized_modifier:2 Toping - Biasa",
		"1 topping besar aja rasa coklat",
		cats,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resolved {
		t.Fatalf("expected resolved = false because 'coklat' is food and must not trigger 'ok' skip confirmation")
	}
}

func TestDraftMerger_TerangBulanMultiToppingClarification(t *testing.T) {
	cats := sampleTerangBulanCatalog()
	provider := &mockCatalogProvider{categories: cats}
	merger := NewDraftMerger(provider)
	ctx := context.Background()

	// Case 1: Terang Bulan 2 Toping has 1 topping (Coklat), customer adds "pisang"
	draftInsufficient := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "m-tb-2-besar",
				SKU:             "TB-2TOPING-BESAR",
				Name:            "Terang Bulan 2 Toping - Besar",
				Quantity:        1,
				UnitPriceAmount: 30000,
				LineTotalAmount: 30000,
				SelectedModifiers: []SelectedModifier{
					{GroupID: "grp-base", GroupName: "Pilihan Base Cake", OptionID: "opt-orig", OptionName: "Original"},
					{GroupID: "grp-top", GroupName: "Pilihan Toping", OptionID: "opt-coklat", OptionName: "Coklat"},
				},
			},
		},
		AmbiguityReasons: []string{"insufficient_toppings:Pilihan Toping:2:1"},
		IsAmbiguous:      true,
		FulfillmentType:  "PICKUP",
		PaymentMethod:    "CASH",
		SubtotalAmount:   30000,
		TotalAmount:      30000,
	}

	updated1, resolved1, err := merger.MergeClarification(
		ctx,
		draftInsufficient,
		"insufficient_toppings:Pilihan Toping:2:1",
		"pisang",
		cats,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !resolved1 {
		t.Fatalf("expected resolved = true when customer provides remaining topping")
	}
	if updated1.IsAmbiguous {
		t.Fatalf("expected unambiguous, got reasons: %v", updated1.AmbiguityReasons)
	}
	// Check toppings: should have Original (base) + Coklat + Pisang = 3 selected modifiers
	var toppingNames []string
	for _, m := range updated1.Items[0].SelectedModifiers {
		if m.GroupName == "Pilihan Toping" {
			toppingNames = append(toppingNames, m.OptionName)
		}
	}
	if len(toppingNames) != 2 {
		t.Fatalf("expected 2 toppings, got %d: %v", len(toppingNames), toppingNames)
	}

	// Case 2: Customer specifies BOTH toppings in clarification ("pisang coklat")
	draftNeedsBoth := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "m-tb-2-besar",
				SKU:             "TB-2TOPING-BESAR",
				Name:            "Terang Bulan 2 Toping - Besar",
				Quantity:        1,
				UnitPriceAmount: 30000,
				LineTotalAmount: 30000,
				SelectedModifiers: []SelectedModifier{
					{GroupID: "grp-base", GroupName: "Pilihan Base Cake", OptionID: "opt-orig", OptionName: "Original"},
				},
			},
		},
		AmbiguityReasons: []string{"missing_required_modifier:Pilihan Toping"},
		IsAmbiguous:      true,
		FulfillmentType:  "PICKUP",
		PaymentMethod:    "CASH",
		SubtotalAmount:   30000,
		TotalAmount:      30000,
	}

	updated2, resolved2, err := merger.MergeClarification(
		ctx,
		draftNeedsBoth,
		"missing_required_modifier:Pilihan Toping",
		"pisang coklat",
		cats,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !resolved2 {
		t.Fatalf("expected resolved = true when providing 'pisang coklat'")
	}
	if updated2.IsAmbiguous {
		t.Fatalf("expected unambiguous, got reasons: %v", updated2.AmbiguityReasons)
	}
	var toppingNames2 []string
	for _, m := range updated2.Items[0].SelectedModifiers {
		if m.GroupName == "Pilihan Toping" {
			toppingNames2 = append(toppingNames2, m.OptionName)
		}
	}
	if len(toppingNames2) != 2 {
		t.Fatalf("expected 2 toppings from 'pisang coklat', got %d: %v", len(toppingNames2), toppingNames2)
	}

	// Case 3: Excess toppings (modifier_limit_exceeded), customer clarifies "keju dan coklat"
	draftExcess := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "m-tb-2-besar",
				SKU:             "TB-2TOPING-BESAR",
				Name:            "Terang Bulan 2 Toping - Besar",
				Quantity:        1,
				UnitPriceAmount: 30000,
				LineTotalAmount: 30000,
				SelectedModifiers: []SelectedModifier{
					{GroupID: "grp-base", GroupName: "Pilihan Base Cake", OptionID: "opt-orig", OptionName: "Original"},
					{GroupID: "grp-top", GroupName: "Pilihan Toping", OptionID: "opt-coklat", OptionName: "Coklat"},
					{GroupID: "grp-top", GroupName: "Pilihan Toping", OptionID: "opt-keju", OptionName: "Keju"},
					{GroupID: "grp-top", GroupName: "Pilihan Toping", OptionID: "opt-pisang", OptionName: "Pisang"},
				},
			},
		},
		AmbiguityReasons: []string{"modifier_limit_exceeded:Pilihan Toping:2:3"},
		IsAmbiguous:      true,
		FulfillmentType:  "PICKUP",
		PaymentMethod:    "CASH",
		SubtotalAmount:   30000,
		TotalAmount:      30000,
	}

	updated3, resolved3, err := merger.MergeClarification(
		ctx,
		draftExcess,
		"modifier_limit_exceeded:Pilihan Toping:2:3",
		"keju dan coklat",
		cats,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !resolved3 {
		t.Fatalf("expected resolved = true when picking 2 toppings from excess")
	}
	if updated3.IsAmbiguous {
		t.Fatalf("expected unambiguous, got reasons: %v", updated3.AmbiguityReasons)
	}
	var toppingNames3 []string
	for _, m := range updated3.Items[0].SelectedModifiers {
		if m.GroupName == "Pilihan Toping" {
			toppingNames3 = append(toppingNames3, m.OptionName)
		}
	}
	if len(toppingNames3) != 2 {
		t.Fatalf("expected exactly 2 toppings after excess clarification, got %d: %v", len(toppingNames3), toppingNames3)
	}
}

