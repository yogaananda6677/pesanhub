package hermes

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/order"
)

type mockOrderCreator struct {
	calls    []order.WhatsAppOrderCreateInput
	createFn func(ctx context.Context, in order.WhatsAppOrderCreateInput, key, reqID string) (order.WhatsAppOrderResponse, bool, error)
}

func (m *mockOrderCreator) CreateWhatsApp(ctx context.Context, in order.WhatsAppOrderCreateInput, key, reqID string) (order.WhatsAppOrderResponse, bool, error) {
	m.calls = append(m.calls, in)
	if m.createFn != nil {
		return m.createFn(ctx, in, key, reqID)
	}
	return order.WhatsAppOrderResponse{
		ID:                  "ord-id-12345",
		OrderNumber:         "ORD-CONFIRM-123",
		PublicTrackingToken: "trk_confirm_token_123",
		Status:              "PENDING",
		TotalAmount:         25000,
		CreatedAt:           time.Now().UTC(),
	}, true, nil
}

func TestService_ProcessTurn_ExplicitConfirmation_CreatesOrder(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	phone := "+6281234567890"

	// Turn 1: Initial order with complete modifiers -> READY_FOR_CONFIRMATION
	turn1, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Pesan nasi goreng spesial 1 pedas",
	})
	if err != nil {
		t.Fatalf("turn 1 error: %v", err)
	}
	if turn1.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s", turn1.State.Status)
	}
	if turn1.State.ConfirmationToken == "" {
		t.Fatal("expected non-empty confirmation token")
	}
	if len(orderCreator.calls) != 0 {
		t.Fatal("order should not be created without customer confirmation")
	}

	// Turn 2: Customer explicitly confirms with "Ya"
	turn2, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Ya",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	if turn2.State.Status != ConversationCompleted {
		t.Fatalf("expected status COMPLETED, got %s", turn2.State.Status)
	}
	if len(orderCreator.calls) != 1 {
		t.Fatalf("expected 1 call to order creator, got %d", len(orderCreator.calls))
	}
	if turn2.Order == nil {
		t.Fatal("expected order summary in turn response")
	}
	if turn2.Order.OrderNumber != "ORD-CONFIRM-123" {
		t.Fatalf("expected order number ORD-CONFIRM-123, got %s", turn2.Order.OrderNumber)
	}
	if !strings.Contains(turn2.ReplyText, "ORD-CONFIRM-123") {
		t.Fatalf("expected reply text to contain order number, got %s", turn2.ReplyText)
	}
	if strings.Contains(turn2.ReplyText, "http") || strings.Contains(turn2.ReplyText, "trk_confirm_token_123") {
		t.Fatalf("reply text must NOT contain web tracking links, got %s", turn2.ReplyText)
	}
	if !strings.Contains(turn2.ReplyText, "PICKUP") {
		t.Fatalf("expected reply text to mention PICKUP, got %s", turn2.ReplyText)
	}
}

func TestService_ProcessTurn_AmbiguousDuringConfirmation_NoOrder(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	phone := "+6281234567890"

	// Turn 1: Initial order -> READY_FOR_CONFIRMATION
	_, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Pesan nasi goreng spesial 1 pedas",
	})
	if err != nil {
		t.Fatalf("turn 1 error: %v", err)
	}

	// Turn 2: Customer sends ambiguous question
	turn2, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Berapa lama jadinya ya kak?",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	if turn2.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected state to remain READY_FOR_CONFIRMATION, got %s", turn2.State.Status)
	}
	if len(orderCreator.calls) != 0 {
		t.Fatal("order must NOT be created on ambiguous response")
	}
	if !strings.Contains(turn2.ReplyText, "belum terkonfirmasi") {
		t.Fatalf("expected guidance prompt, got %s", turn2.ReplyText)
	}
}

func TestService_ProcessTurn_CancellationDuringConfirmation(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	phone := "+6281234567890"

	// Turn 1: Initial order -> READY_FOR_CONFIRMATION
	_, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Pesan nasi goreng spesial 1 pedas",
	})
	if err != nil {
		t.Fatalf("turn 1 error: %v", err)
	}

	// Turn 2: Customer cancels with "Batal"
	turn2, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Batal kak gak jadi",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	if turn2.State.Status != ConversationCollecting {
		t.Fatalf("expected state reset to COLLECTING, got %s", turn2.State.Status)
	}
	if turn2.State.CurrentDraft != nil {
		t.Fatal("expected draft to be cleared on cancellation")
	}
	if len(orderCreator.calls) != 0 {
		t.Fatal("order must NOT be created on cancellation")
	}
	if !strings.Contains(turn2.ReplyText, "dibatalkan") {
		t.Fatalf("expected cancellation acknowledgement, got %s", turn2.ReplyText)
	}
}

func TestService_ProcessTurn_StaleDraftPriceChange_RequiresReconfirmation(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	initialCat := sampleCatalog()
	catProvider := &mockCatalogProvider{categories: initialCat}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	phone := "+6281234567890"

	// Turn 1: Initial order -> READY_FOR_CONFIRMATION (Price = 25000)
	turn1, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Pesan nasi goreng spesial 1 pedas",
	})
	if err != nil {
		t.Fatalf("turn 1 error: %v", err)
	}
	if turn1.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s", turn1.State.Status)
	}

	// Price changes in catalog before confirmation!
	updatedCat := sampleCatalog()
	updatedCat[0].Menus[0].PriceAmount = 28000
	catProvider.categories = updatedCat

	// Turn 2: Customer confirms with "Ya" -> price change detected!
	turn2, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Ya",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	// Must NOT create order
	if len(orderCreator.calls) != 0 {
		t.Fatal("order must NOT be created when draft price changed")
	}
	// Must stay in READY_FOR_CONFIRMATION with updated total
	if turn2.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected state READY_FOR_CONFIRMATION, got %s", turn2.State.Status)
	}
	if turn2.Draft.TotalAmount != 28000 {
		t.Fatalf("expected draft total updated to 28000, got %d", turn2.Draft.TotalAmount)
	}
	if !strings.Contains(turn2.ReplyText, "perubahan") || !strings.Contains(turn2.ReplyText, "28000") {
		t.Fatalf("expected price change alert with 28000, got %s", turn2.ReplyText)
	}

	// Turn 3: Customer confirms the new total -> order is now created!
	turn3, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Oke saya setuju",
	})
	if err != nil {
		t.Fatalf("turn 3 error: %v", err)
	}
	if turn3.State.Status != ConversationCompleted {
		t.Fatalf("expected status COMPLETED after re-confirmation, got %s", turn3.State.Status)
	}
	if len(orderCreator.calls) != 1 {
		t.Fatalf("expected exactly 1 order creation, got %d", len(orderCreator.calls))
	}
}

func TestService_ProcessTurn_DuplicateConfirmation_Idempotent(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	callCount := 0
	orderCreator := &mockOrderCreator{
		createFn: func(ctx context.Context, in order.WhatsAppOrderCreateInput, key, reqID string) (order.WhatsAppOrderResponse, bool, error) {
			callCount++
			isNew := callCount == 1
			return order.WhatsAppOrderResponse{
				ID:                  "ord-id-idempotent",
				OrderNumber:         "ORD-IDEMPOTENT-1",
				PublicTrackingToken: "trk_idempotent_1",
				Status:              "PENDING",
				TotalAmount:         25000,
				CreatedAt:           time.Now().UTC(),
			}, isNew, nil
		},
	}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	phone := "+6281234567890"

	// Turn 1: Initial order
	_, _ = svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Pesan nasi goreng spesial 1 pedas",
	})

	// Turn 2: First confirmation
	turn2, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Ya",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	if turn2.Order.OrderNumber != "ORD-IDEMPOTENT-1" {
		t.Fatalf("expected ORD-IDEMPOTENT-1, got %s", turn2.Order.OrderNumber)
	}

	// Turn 3: Duplicate webhook delivery of "Ya" or customer sends "ok" after completion
	turn3, err := svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "ok",
	})
	if err != nil {
		t.Fatalf("turn 3 error: %v", err)
	}
	// In COMPLETED status, "ok" is an acknowledgment and does not duplicate order
	if len(orderCreator.calls) != 1 {
		t.Fatalf("order creator should only be called once, got %d", len(orderCreator.calls))
	}
	if !strings.Contains(turn3.ReplyText, "Sama-sama") {
		t.Fatalf("expected acknowledgment reply, got %s", turn3.ReplyText)
	}
}

func TestService_ProcessTurn_OrderCreationFailure_ThresholdHandoff(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{
		createFn: func(ctx context.Context, in order.WhatsAppOrderCreateInput, key, reqID string) (order.WhatsAppOrderResponse, bool, error) {
			return order.WhatsAppOrderResponse{}, false, errors.New("database connection refused")
		},
	}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	phone := "+6281234567890"

	// Turn 1: Initial order -> READY_FOR_CONFIRMATION
	_, _ = svc.ProcessTurn(context.Background(), TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Pesan nasi goreng spesial 1 pedas",
	})

	// Turn 2: Failure 1
	_, err := svc.ProcessTurn(context.Background(), TurnRequest{Session: "default", SenderPhone: phone, MessageText: "Ya"})
	if err == nil {
		t.Fatal("expected error on failure 1")
	}

	// Turn 3: Failure 2
	_, err = svc.ProcessTurn(context.Background(), TurnRequest{Session: "default", SenderPhone: phone, MessageText: "Ya"})
	if err == nil {
		t.Fatal("expected error on failure 2")
	}

	// Turn 4: Failure 3 -> triggers staff handoff!
	turn4, err := svc.ProcessTurn(context.Background(), TurnRequest{Session: "default", SenderPhone: phone, MessageText: "Ya"})
	if err != nil {
		t.Fatalf("turn 4 should not return hard error when handing off: %v", err)
	}
	if !turn4.RequiresHandoff {
		t.Fatal("expected RequiresHandoff = true")
	}
	if turn4.State.Status != ConversationHandoff {
		t.Fatalf("expected state HANDOFF, got %s", turn4.State.Status)
	}
	if turn4.State.HandoffPriority != HandoffPriorityHigh {
		t.Fatalf("expected handoff priority HIGH, got %s", turn4.State.HandoffPriority)
	}
}

func TestService_ProcessTurn_AddItemsDuringConfirmation(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	ctx := context.Background()
	phone := "+6289516122795"

	// Turn 1: Initial item
	turn1, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "Pesan nasi goreng spesial 1 pedas",
	})
	if err != nil {
		t.Fatalf("turn 1 error: %v", err)
	}
	if turn1.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s", turn1.State.Status)
	}
	if len(turn1.Draft.Items) != 1 {
		t.Fatalf("expected 1 item in draft, got %d", len(turn1.Draft.Items))
	}
	if len(orderCreator.calls) != 0 {
		t.Fatal("order should not be created yet")
	}

	// Turn 2: Customer wants to add items ("iya nambah pesanan lagi")
	// The mock client will return 0 items for extraction of "iya nambah pesanan lagi"
	mockClient.Response = &RawExtractedOrder{
		Items:           []RawExtractedItem{},
		Confidence:      0.95,
		FulfillmentType: "PICKUP",
		PaymentMethod:   "CASH",
	}

	turn2, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "iya nambah pesanan lagi",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	// Crucial check: MUST NOT create order
	if len(orderCreator.calls) != 0 {
		t.Fatal("order MUST NOT be created when customer asks to add more items!")
	}
	if !strings.Contains(turn2.ReplyText, "Boleh banget kak Yoga! Mau nambah menu apa lagi nih?") {
		t.Fatalf("expected friendly prompt for additional items, got:\n%s", turn2.ReplyText)
	}
	if !strings.HasSuffix(turn2.ReplyText, "~AI Jenggirat") {
		t.Fatalf("expected signature ~AI Jenggirat, got:\n%s", turn2.ReplyText)
	}
	if turn2.State.PendingAmbiguity != "awaiting_additional_items" {
		t.Fatalf("expected PendingAmbiguity to be awaiting_additional_items, got %s", turn2.State.PendingAmbiguity)
	}

	// Turn 3: Customer provides 2nd item
	mockClient.Response = &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   "Nasi Goreng Spesial",
				Quantity:   1,
				Modifiers:  []string{"Sedang"},
				Confidence: 0.95,
			},
		},
		FulfillmentType: "PICKUP",
		PaymentMethod:   "CASH",
		Confidence:      0.95,
	}

	turn3, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "nasi goreng spesial 1 sedang",
	})
	if err != nil {
		t.Fatalf("turn 3 error: %v", err)
	}
	if len(turn3.Draft.Items) != 2 {
		t.Fatalf("expected draft to contain 2 items, got %d", len(turn3.Draft.Items))
	}
	if turn3.Draft.TotalAmount != 40000 {
		t.Fatalf("expected total amount 40000 (2x20000), got %d", turn3.Draft.TotalAmount)
	}
	if strings.Contains(turn3.ReplyText, "Dine In") {
		t.Fatalf("reply must NEVER mention Dine In, got:\n%s", turn3.ReplyText)
	}
	if !strings.Contains(turn3.ReplyText, "PICKUP (Bawa Pulang)") {
		t.Fatalf("reply must specify PICKUP (Bawa Pulang), got:\n%s", turn3.ReplyText)
	}
	if !strings.HasSuffix(turn3.ReplyText, "~AI Jenggirat") {
		t.Fatalf("expected signature ~AI Jenggirat, got:\n%s", turn3.ReplyText)
	}

	// Turn 4: Customer explicitly confirms
	turn4, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "ya siap bungkus",
	})
	if err != nil {
		t.Fatalf("turn 4 error: %v", err)
	}
	if turn4.State.Status != ConversationCompleted {
		t.Fatalf("expected status COMPLETED, got %s", turn4.State.Status)
	}
	if len(orderCreator.calls) != 1 {
		t.Fatalf("expected 1 call to order creator, got %d", len(orderCreator.calls))
	}
	if len(orderCreator.calls[0].Items) != 2 {
		t.Fatalf("expected order to have 2 items, got %d", len(orderCreator.calls[0].Items))
	}
	if orderCreator.calls[0].CustomerName != "Yoga" {
		t.Fatalf("expected customer name Yoga, got %s", orderCreator.calls[0].CustomerName)
	}
	if !strings.HasSuffix(turn4.ReplyText, "~AI Jenggirat") {
		t.Fatalf("expected signature ~AI Jenggirat, got:\n%s", turn4.ReplyText)
	}
}

func TestService_ProcessTurn_AddItemsWithLLMClarification(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	ctx := context.Background()
	phone := "+6289516122795"

	// Turn 1: Initial item
	turn1, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "Pesan nasi goreng spesial 1 pedas",
	})
	if err != nil {
		t.Fatalf("turn 1 error: %v", err)
	}
	if turn1.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s", turn1.State.Status)
	}

	// Turn 2: Customer wants to add drinks, LLM returns conversational clarifying question
	mockClient.Response = &RawExtractedOrder{
		Items:           []RawExtractedItem{},
		Confidence:      0.90,
		ReplyText:       "Mau tambah minuman apa kak? Kami ada Es Teh Manis yang segar banget!",
		FulfillmentType: "PICKUP",
		PaymentMethod:   "CASH",
	}

	turn2, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "tambah minum dong",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	if len(orderCreator.calls) != 0 {
		t.Fatal("order MUST NOT be created when customer asks to add more items!")
	}
	if !strings.Contains(turn2.ReplyText, "Kami ada Es Teh Manis yang segar banget!") {
		t.Fatalf("expected LLM clarifying question to be preserved, got:\n%s", turn2.ReplyText)
	}
	if turn2.State.Status != ConversationAwaitingClarification {
		t.Fatalf("expected status AWAITING_CLARIFICATION, got %s", turn2.State.Status)
	}
	if turn2.State.PendingAmbiguity != "awaiting_additional_items" {
		t.Fatalf("expected PendingAmbiguity awaiting_additional_items, got %s", turn2.State.PendingAmbiguity)
	}

	// Turn 3: Customer chooses "es teh manis 1"
	mockClient.Response = &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   "Es Teh Manis",
				Quantity:   1,
				Confidence: 0.95,
			},
		},
		FulfillmentType: "PICKUP",
		PaymentMethod:   "CASH",
		Confidence:      0.95,
	}

	turn3, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "es teh manis 1",
	})
	if err != nil {
		t.Fatalf("turn 3 error: %v", err)
	}
	if turn3.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s", turn3.State.Status)
	}
	if len(turn3.Draft.Items) != 2 {
		t.Fatalf("expected 2 items in draft, got %d", len(turn3.Draft.Items))
	}
	if turn3.Draft.TotalAmount != 25000 {
		t.Fatalf("expected total amount 25000 (20000 + 5000), got %d", turn3.Draft.TotalAmount)
	}
	if !strings.Contains(turn3.ReplyText, "Es Teh Manis") || !strings.Contains(turn3.ReplyText, "Nasi Goreng Spesial") {
		t.Fatalf("expected both items in confirmation summary, got:\n%s", turn3.ReplyText)
	}

	// Turn 4: Confirm
	turn4, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "oke deal",
	})
	if err != nil {
		t.Fatalf("turn 4 error: %v", err)
	}
	if turn4.State.Status != ConversationCompleted {
		t.Fatalf("expected COMPLETED, got %s", turn4.State.Status)
	}
	if len(orderCreator.calls) != 1 {
		t.Fatalf("expected 1 order call, got %d", len(orderCreator.calls))
	}
	if len(orderCreator.calls[0].Items) != 2 {
		t.Fatalf("expected 2 items in created order, got %d", len(orderCreator.calls[0].Items))
	}
}

func TestService_ProcessTurn_ModifyOrder_NoDuplication(t *testing.T) {
	catProvider := &mockCatalogProvider{categories: sampleTerangBulanCatalog()}
	convStore := NewMemoryConversationStore()
	orderCreator := &mockOrderCreator{}

	// Turn 1: Initial order of "Terang Bulan 2 Toping - Besar" with Pisang Coklat
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Terang Bulan 2 Toping - Besar",
					Quantity:   1,
					Modifiers:  []string{"pisang", "coklat"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "CASH",
			Confidence:      0.95,
		},
	}

	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   catProvider,
		OrderCreator:      orderCreator,
		ConversationStore: convStore,
	})

	phone := "+6281234567890"
	ctx := context.Background()

	turn1, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "pesan terang bulan 2 toping pisang coklat",
	})
	if err != nil {
		t.Fatalf("turn 1 error: %v", err)
	}
	if turn1.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s", turn1.State.Status)
	}
	if len(turn1.Draft.Items) != 1 {
		t.Fatalf("expected 1 item in draft, got %d", len(turn1.Draft.Items))
	}
	if turn1.Draft.TotalAmount != 30000 {
		t.Fatalf("expected total amount 30000, got %d", turn1.Draft.TotalAmount)
	}

	// Turn 2: Customer modifies to "Diubah, 2 toping keju dan coklat"
	// LLM extracts the modified order
	mockClient.Response = &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   "Terang Bulan 2 Toping - Besar",
				Quantity:   1,
				Modifiers:  []string{"keju", "coklat"},
				Confidence: 0.95,
			},
		},
		FulfillmentType: "PICKUP",
		PaymentMethod:   "CASH",
		Confidence:      0.95,
	}

	turn2, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "Diubah, 2 toping keju dan coklat",
	})
	if err != nil {
		t.Fatalf("turn 2 error: %v", err)
	}
	if turn2.State.Status != ConversationReadyForConfirmation {
		t.Fatalf("expected status READY_FOR_CONFIRMATION, got %s", turn2.State.Status)
	}
	// CRITICAL CHECK: Items count must still be 1 (replaced, NOT duplicated to 2 items / 60.000!)
	if len(turn2.Draft.Items) != 1 {
		t.Fatalf("expected 1 item after modification (anti-duplication), got %d items", len(turn2.Draft.Items))
	}
	if turn2.Draft.TotalAmount != 30000 {
		t.Fatalf("expected total amount 30000 (NOT doubled to 60000), got %d", turn2.Draft.TotalAmount)
	}

	// Turn 3: Customer confirms "ya deal"
	turn3, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:      "default",
		SenderPhone:  phone,
		CustomerName: "Yoga",
		MessageText:  "ya deal",
	})
	if err != nil {
		t.Fatalf("turn 3 error: %v", err)
	}
	if turn3.State.Status != ConversationCompleted {
		t.Fatalf("expected status COMPLETED, got %s", turn3.State.Status)
	}
	if len(orderCreator.calls) != 1 {
		t.Fatalf("expected 1 order created, got %d", len(orderCreator.calls))
	}
	if len(orderCreator.calls[0].Items) != 1 {
		t.Fatalf("expected 1 item in created order, got %d", len(orderCreator.calls[0].Items))
	}
}


