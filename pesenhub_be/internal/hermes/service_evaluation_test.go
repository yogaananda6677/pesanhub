package hermes

import (
	"context"
	"strings"
	"testing"

	"pesenhub/backend/internal/catalog"
)

func TestService_FormatOrderSummaryProductPrefix(t *testing.T) {
	draft := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "m-tb-2-biasa",
				Name:            "Terang Bulan 2 Toping - Biasa",
				Quantity:        1,
				UnitPriceAmount: 23000,
				LineTotalAmount: 23000,
				SelectedModifiers: []SelectedModifier{
					{OptionName: "Original", PriceDeltaAmount: 0},
					{OptionName: "Coklat", PriceDeltaAmount: 0},
					{OptionName: "Keju", PriceDeltaAmount: 0},
				},
			},
			{
				MenuID:          "m-sapi-biasa",
				Name:            "Martabak Daging Sapi - Biasa",
				Quantity:        1,
				UnitPriceAmount: 30000,
				LineTotalAmount: 30000,
			},
		},
		SubtotalAmount:  53000,
		TotalAmount:     53000,
		FulfillmentType: "PICKUP",
	}

	summary := formatOrderSummary(draft, "IdontCare")

	// 1. Must use "1x " instead of "1 1"
	if !strings.Contains(summary, "- 1x Terang Bulan 2 Toping - Biasa") {
		t.Errorf("expected '- 1x Terang Bulan 2 Toping - Biasa', got:\n%s", summary)
	}

	// 2. Must omit "Original" from modifiers if delta is 0
	if strings.Contains(summary, "Original") {
		t.Errorf("expected 0-delta Original to be omitted from modifiers, got:\n%s", summary)
	}
	if !strings.Contains(summary, "(Coklat, Keju)") {
		t.Errorf("expected '(Coklat, Keju)', got:\n%s", summary)
	}

	// 3. Second item format
	if !strings.Contains(summary, "- 1x Martabak Daging Sapi - Biasa: Rp 30000") {
		t.Errorf("expected second item formatted with 1x and price, got:\n%s", summary)
	}

	// 4. Fulfillment description
	if !strings.Contains(summary, "Pengambilan: PICKUP (Bawa Pulang)") {
		t.Errorf("expected clear fulfillment description, got:\n%s", summary)
	}
}

func TestService_ProcessTurn_TambahAppendsToDraft(t *testing.T) {
	categories := []catalog.Category{
		{
			ID:     "cat-tb",
			Name:   "Terang Bulan Manis",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "m-tb-1",
					SKU:         "TB-1TOPING-BESAR",
					Name:        "1 Toping - Besar",
					PriceAmount: 25000,
					Available:   true,
					Groups: []catalog.Group{
						{
							ID:        "grp-base",
							Name:      "Pilihan Base Cake",
							MinSelect: 1,
							MaxSelect: 1,
							Active:    true,
							Options: []catalog.Option{
								{ID: "opt-orig", Code: "original", Name: "Original", PriceDeltaAmount: 0, Available: true},
							},
						},
						{
							ID:        "grp-top",
							Name:      "Pilihan Toping",
							MinSelect: 1,
							MaxSelect: 8,
							Active:    true,
							Options: []catalog.Option{
								{ID: "opt-coklat", Code: "coklat", Name: "Coklat", PriceDeltaAmount: 0, Available: true},
							},
						},
					},
				},
			},
		},
		{
			ID:     "cat-sapi",
			Name:   "Daging Sapi",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "m-sapi-biasa",
					SKU:         "MT-SAPI-BIASA",
					Name:        "Biasa",
					PriceAmount: 30000,
					Available:   true,
				},
			},
		},
	}

	mockCatalog := &mockCatalogProvider{categories: categories}
	mockLLM := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "martabak telur daging sapi",
					Modifiers:  []string{"Biasa"},
					Quantity:   1,
					Confidence: 0.95,
				},
			},
			Confidence:      0.95,
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
		},
	}

	convStore := NewMemoryConversationStore()
	svc := NewService(Config{
		Client:              mockLLM,
		CatalogProvider:     mockCatalog,
		ConversationStore:   convStore,
		ConfidenceThreshold: 0.75,
	})

	phone := "+6289516122795"

	// Pre-seed draft in READY_FOR_CONFIRMATION
	existingDraft := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "m-tb-1",
				Name:            "Terang Bulan 1 Toping - Besar",
				Quantity:        1,
				UnitPriceAmount: 25000,
				LineTotalAmount: 25000,
				SelectedModifiers: []SelectedModifier{
					{OptionName: "Original", PriceDeltaAmount: 0},
					{OptionName: "Coklat", PriceDeltaAmount: 0},
				},
			},
		},
		SubtotalAmount:  25000,
		TotalAmount:     25000,
		FulfillmentType: "PICKUP",
		PaymentMethod:   "CASH",
	}

	_ = convStore.Save(context.Background(), &ConversationState{
		ID:            "conv-1",
		Session:       "default",
		CustomerPhone: phone,
		CustomerName:  "IdontCare",
		Status:        ConversationReadyForConfirmation,
		CurrentDraft:  existingDraft,
		DraftVersion:  1,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "tambah martabak telur daging sapi biasa 1",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Must remain in READY_FOR_CONFIRMATION and have 2 items!
	if resp.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s (PendingAmbiguity: %s, Reply: %s)", resp.State.Status, resp.State.PendingAmbiguity, resp.ReplyText)
	}

	if len(resp.Draft.Items) != 2 {
		t.Fatalf("expected draft to have 2 items, got %d", len(resp.Draft.Items))
	}

	if resp.Draft.TotalAmount != 55000 {
		t.Errorf("expected total 55000 (25000 + 30000), got %d", resp.Draft.TotalAmount)
	}

	if !strings.Contains(resp.ReplyText, "Terang Bulan") || !strings.Contains(resp.ReplyText, "Martabak") {
		t.Errorf("expected reply summary to contain both items, got:\n%s", resp.ReplyText)
	}
}

func TestService_ProcessTurn_ActiveDraftStatusCheck(t *testing.T) {
	categories := []catalog.Category{
		{
			ID:     "cat-tb",
			Name:   "Terang Bulan Manis",
			Active: true,
			Menus: []catalog.Menu{
				{ID: "m-tb-1", Name: "1 Toping - Biasa", PriceAmount: 18000, Available: true},
			},
		},
	}

	convStore := NewMemoryConversationStore()
	svc := NewService(Config{
		Client:              &MockLLMClient{},
		CatalogProvider:     &mockCatalogProvider{categories: categories},
		ConversationStore:   convStore,
		ConfidenceThreshold: 0.75,
	})

	phone := "+6289516122795"

	activeDraft := &DraftCandidate{
		Items: []ExtractedItem{
			{
				MenuID:          "m-tb-1",
				Name:            "Terang Bulan 1 Toping - Biasa",
				Quantity:        1,
				UnitPriceAmount: 18000,
				LineTotalAmount: 18000,
				SelectedModifiers: []SelectedModifier{
					{OptionName: "Coklat", PriceDeltaAmount: 0},
				},
			},
		},
		SubtotalAmount:  18000,
		TotalAmount:     18000,
		FulfillmentType: "PICKUP",
	}

	_ = convStore.Save(context.Background(), &ConversationState{
		ID:            "conv-2",
		Session:       "default",
		CustomerPhone: phone,
		CustomerName:  "IdontCare",
		Status:        ConversationReadyForConfirmation,
		CurrentDraft:  activeDraft,
		DraftVersion:  1,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "cek pesanan saya apa aja",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(resp.ReplyText, "Terang Bulan 1 Toping - Biasa") {
		t.Errorf("expected current draft items in reply, got:\n%s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "18000") {
		t.Errorf("expected total price in reply, got:\n%s", resp.ReplyText)
	}
}
