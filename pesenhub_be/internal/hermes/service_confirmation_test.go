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
	if !strings.Contains(turn2.ReplyText, "trk_confirm_token_123") {
		t.Fatalf("expected reply text to contain tracking token, got %s", turn2.ReplyText)
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
