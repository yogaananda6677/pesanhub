package hermes

import (
	"context"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/order"
)

type mockOrderTransitioner struct {
	transitions []struct {
		orderID      string
		targetStatus string
	}
}

func (m *mockOrderTransitioner) Transition(ctx context.Context, orderID string, in order.TransitionInput, idempotencyKey, actorID, actorType, requestID string) (order.StatusResult, bool, error) {
	m.transitions = append(m.transitions, struct {
		orderID      string
		targetStatus string
	}{
		orderID:      orderID,
		targetStatus: in.TargetStatus,
	})
	return order.StatusResult{
		ID:     orderID,
		Status: in.TargetStatus,
	}, true, nil
}

type mockOrderReaderWithOrders struct {
	orders map[string]order.OrderDetail
}

func (m *mockOrderReaderWithOrders) GetByID(ctx context.Context, orderID string) (order.OrderDetail, error) {
	if ord, ok := m.orders[orderID]; ok {
		return ord, nil
	}
	return order.OrderDetail{}, nil
}

func (m *mockOrderReaderWithOrders) GetLatestByPhone(ctx context.Context, phone string) (order.OrderDetail, error) {
	for _, ord := range m.orders {
		if ord.CustomerPhone != nil && *ord.CustomerPhone == phone {
			return ord, nil
		}
	}
	return order.OrderDetail{}, nil
}

func TestOrderCancellation_TwoStep_ConfirmSuccess(t *testing.T) {
	phone := "+6281234567890"
	ordID := "ord-active-1"
	ordNum := "BWX-20261101-0001"

	transitioner := &mockOrderTransitioner{}
	reader := &mockOrderReaderWithOrders{
		orders: map[string]order.OrderDetail{
			ordID: {
				ID:            ordID,
				OrderNumber:   ordNum,
				CustomerName:  "Budi",
				CustomerPhone: &phone,
				Status:        "PENDING",
				TotalAmount:   50000,
				Version:       1,
				CreatedAt:     time.Now().UTC(),
			},
		},
	}

	memStore := NewMemoryConversationStore()
	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   &mockCatalogProvider{categories: []catalog.Category{}},
		OrderReader:       reader,
		OrderTransitioner: transitioner,
		ConversationStore: memStore,
	})

	ctx := context.Background()

	// Step 1: Customer asks to cancel order
	resp1, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "kak mau batalkan pesanan saya dong",
	})
	if err != nil {
		t.Fatalf("Step 1 failed: %v", err)
	}

	// Should NOT transition yet (2-step confirmation)
	if len(transitioner.transitions) != 0 {
		t.Fatalf("expected 0 transitions in Step 1, got %d", len(transitioner.transitions))
	}
	if !strings.Contains(resp1.ReplyText, ordNum) {
		t.Errorf("expected order number in reply, got: %s", resp1.ReplyText)
	}
	if !strings.Contains(resp1.ReplyText, "YA BATALKAN") {
		t.Errorf("expected prompt for YA BATALKAN, got: %s", resp1.ReplyText)
	}
	if resp1.State.PendingAmbiguity != "awaiting_cancel_order_confirmation" {
		t.Errorf("expected state awaiting_cancel_order_confirmation, got %s", resp1.State.PendingAmbiguity)
	}

	// Step 2: Customer confirms cancellation with "YA BATALKAN"
	resp2, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "YA BATALKAN",
	})
	if err != nil {
		t.Fatalf("Step 2 failed: %v", err)
	}

	// Transition should be executed
	if len(transitioner.transitions) != 1 {
		t.Fatalf("expected 1 transition in Step 2, got %d", len(transitioner.transitions))
	}
	if transitioner.transitions[0].targetStatus != "CANCELLED" {
		t.Errorf("expected targetStatus CANCELLED, got %s", transitioner.transitions[0].targetStatus)
	}
	if !strings.Contains(resp2.ReplyText, "berhasil dibatalkan") {
		t.Errorf("expected success cancellation message, got: %s", resp2.ReplyText)
	}
	if resp2.State.PendingAmbiguity != "" {
		t.Errorf("expected cleared PendingAmbiguity, got: %s", resp2.State.PendingAmbiguity)
	}
}

func TestOrderCancellation_TwoStep_RejectedKeepOrder(t *testing.T) {
	phone := "+6281234567890"
	ordID := "ord-active-2"
	ordNum := "BWX-20261101-0002"

	transitioner := &mockOrderTransitioner{}
	reader := &mockOrderReaderWithOrders{
		orders: map[string]order.OrderDetail{
			ordID: {
				ID:            ordID,
				OrderNumber:   ordNum,
				CustomerName:  "Siti",
				CustomerPhone: &phone,
				Status:        "ACCEPTED",
				TotalAmount:   75000,
				Version:       2,
				CreatedAt:     time.Now().UTC(),
			},
		},
	}

	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   &mockCatalogProvider{categories: []catalog.Category{}},
		OrderReader:       reader,
		OrderTransitioner: transitioner,
		ConversationStore: NewMemoryConversationStore(),
	})

	ctx := context.Background()

	// Step 1: Customer requests cancellation
	resp1, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "batalin order",
	})
	if err != nil {
		t.Fatalf("Step 1 failed: %v", err)
	}
	if resp1.State.PendingAmbiguity != "awaiting_cancel_order_confirmation" {
		t.Fatalf("expected state awaiting_cancel_order_confirmation, got %s", resp1.State.PendingAmbiguity)
	}

	// Step 2: Customer changes their mind: "gak jadi batal kak, lanjut aja"
	resp2, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "gak jadi batal kak, lanjut aja",
	})
	if err != nil {
		t.Fatalf("Step 2 failed: %v", err)
	}

	// NO transition should occur
	if len(transitioner.transitions) != 0 {
		t.Fatalf("expected 0 transitions, got %d", len(transitioner.transitions))
	}
	if !strings.Contains(resp2.ReplyText, "tetap diproses") {
		t.Errorf("expected keep order message, got: %s", resp2.ReplyText)
	}
	if resp2.State.PendingAmbiguity != "" {
		t.Errorf("expected cleared PendingAmbiguity, got: %s", resp2.State.PendingAmbiguity)
	}
}

func TestOrderCancellation_OrderAlreadyInKitchen_CannotCancel(t *testing.T) {
	phone := "+6281234567890"
	ordID := "ord-kitchen-1"
	ordNum := "BWX-20261101-0003"

	transitioner := &mockOrderTransitioner{}
	reader := &mockOrderReaderWithOrders{
		orders: map[string]order.OrderDetail{
			ordID: {
				ID:            ordID,
				OrderNumber:   ordNum,
				CustomerName:  "Rudi",
				CustomerPhone: &phone,
				Status:        "PREPARING",
				TotalAmount:   40000,
				Version:       3,
				CreatedAt:     time.Now().UTC(),
			},
		},
	}

	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   &mockCatalogProvider{categories: []catalog.Category{}},
		OrderReader:       reader,
		OrderTransitioner: transitioner,
		ConversationStore: NewMemoryConversationStore(),
	})

	ctx := context.Background()

	resp, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "batalkan pesanan saya kak",
	})
	if err != nil {
		t.Fatalf("Turn failed: %v", err)
	}

	if len(transitioner.transitions) != 0 {
		t.Fatalf("expected 0 transitions, got %d", len(transitioner.transitions))
	}
	if !strings.Contains(resp.ReplyText, "tidak dapat dibatalkan") {
		t.Errorf("expected cannot cancel message, got: %s", resp.ReplyText)
	}
}
