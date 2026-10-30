package order

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"

	"pesenhub/backend/internal/notification"
)

type mockNotifier struct {
	dispatchCalls int64
	lastType      notification.NotificationType
	lastData      notification.OrderNotificationData
	dispatchErr   error
}

func (m *mockNotifier) Dispatch(ctx context.Context, notifType notification.NotificationType, data notification.OrderNotificationData) (*notification.NotificationResult, error) {
	atomic.AddInt64(&m.dispatchCalls, 1)
	m.lastType = notifType
	m.lastData = data
	if m.dispatchErr != nil {
		return &notification.NotificationResult{
			OrderID:          data.OrderID,
			NotificationType: notifType,
			Status:           notification.StatusFailed,
			Error:            m.dispatchErr,
		}, nil
	}
	return &notification.NotificationResult{
		OrderID:          data.OrderID,
		NotificationType: notifType,
		Status:           notification.StatusSent,
	}, nil
}

func (m *mockNotifier) NotifyConfirmation(ctx context.Context, data notification.OrderNotificationData) (*notification.NotificationResult, error) {
	return m.Dispatch(ctx, notification.TypeConfirmation, data)
}

func (m *mockNotifier) NotifyAccepted(ctx context.Context, data notification.OrderNotificationData) (*notification.NotificationResult, error) {
	return m.Dispatch(ctx, notification.TypeAccepted, data)
}

func (m *mockNotifier) NotifyCompleted(ctx context.Context, data notification.OrderNotificationData) (*notification.NotificationResult, error) {
	return m.Dispatch(ctx, notification.TypeCompleted, data)
}

type mockOrderReader struct {
	detail OrderDetail
	err    error
}

func (m *mockOrderReader) List(ctx context.Context, f OrderFilter) ([]OrderDetail, string, error) {
	return []OrderDetail{m.detail}, "", nil
}

func (m *mockOrderReader) GetByID(ctx context.Context, id string) (OrderDetail, error) {
	if m.err != nil {
		return OrderDetail{}, m.err
	}
	return m.detail, nil
}

func TestNotificationDispatcher_CompletedTransition(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:                  "ord-123",
			OrderNumber:         "ORD-COMPLETED-1",
			CustomerName:        "Siti",
			CustomerPhone:       &phone,
			Status:              "COMPLETED",
			TotalAmount:         35000,
			PublicTrackingToken: "trk_completed_123",
			Items: []OrderItemDetail{
				{Name: "Nasi Goreng", Quantity: 1, UnitPriceAmount: 35000, LineTotalAmount: 35000},
			},
		},
	}
	notif := &mockNotifier{}
	dispatcher := NewNotificationDispatcher(reader, notif, nil)

	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "READY_FOR_PICKUP", "COMPLETED")

	if notif.dispatchCalls != 1 {
		t.Fatalf("expected 1 dispatch call, got %d", notif.dispatchCalls)
	}
	if notif.lastType != notification.TypeCompleted {
		t.Fatalf("expected TypeCompleted, got %s", notif.lastType)
	}
	if notif.lastData.OrderID != "ord-123" || notif.lastData.OrderNumber != "ORD-COMPLETED-1" {
		t.Fatalf("unexpected order data in notification: %+v", notif.lastData)
	}
	if notif.lastData.CustomerPhone != "+6281234567890" {
		t.Fatalf("expected phone +6281234567890, got %s", notif.lastData.CustomerPhone)
	}
}

func TestNotificationDispatcher_AcceptedTransition(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:                  "ord-123",
			OrderNumber:         "ORD-ACCEPTED-1",
			CustomerName:        "Siti",
			CustomerPhone:       &phone,
			Status:              "ACCEPTED",
			TotalAmount:         35000,
			PublicTrackingToken: "trk_accepted_123",
		},
	}
	notif := &mockNotifier{}
	dispatcher := NewNotificationDispatcher(reader, notif, nil)

	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "PENDING", "ACCEPTED")

	if notif.dispatchCalls != 1 {
		t.Fatalf("expected 1 dispatch call, got %d", notif.dispatchCalls)
	}
	if notif.lastType != notification.TypeAccepted {
		t.Fatalf("expected TypeAccepted, got %s", notif.lastType)
	}
}

func TestNotificationDispatcher_AcceptedTransition_WhatsAppSuppressed(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:                  "ord-123",
			OrderNumber:         "ORD-ACCEPTED-WA-1",
			Source:              "WHATSAPP",
			CustomerName:        "Yoga",
			CustomerPhone:       &phone,
			Status:              "ACCEPTED",
			TotalAmount:         35000,
			PublicTrackingToken: "trk_accepted_wa_123",
		},
	}
	notif := &mockNotifier{}
	dispatcher := NewNotificationDispatcher(reader, notif, nil)

	// ACCEPTED notification for WHATSAPP order should be suppressed
	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "PENDING", "ACCEPTED")

	if notif.dispatchCalls != 0 {
		t.Fatalf("expected 0 dispatch calls for WHATSAPP order ACCEPTED transition, got %d", notif.dispatchCalls)
	}
}

type mockNameResolver struct {
	name string
	err  error
}

func (m *mockNameResolver) Get(ctx context.Context, phone string) (string, error) {
	return m.name, m.err
}

func TestNotificationDispatcher_CustomerNameResolver(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:                  "ord-123",
			OrderNumber:         "ORD-READY-1",
			CustomerName:        "OldSnapshotName",
			CustomerPhone:       &phone,
			Status:              "READY_FOR_PICKUP",
			TotalAmount:         35000,
			PublicTrackingToken: "trk_ready_123",
		},
	}
	notif := &mockNotifier{}
	resolver := &mockNameResolver{name: "Yoga"}
	dispatcher := NewNotificationDispatcher(reader, notif, nil, resolver)

	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "PREPARING", "READY_FOR_PICKUP")

	if notif.dispatchCalls != 1 {
		t.Fatalf("expected 1 dispatch call, got %d", notif.dispatchCalls)
	}
	if notif.lastData.CustomerName != "Yoga" {
		t.Fatalf("expected resolved customer name 'Yoga', got '%s'", notif.lastData.CustomerName)
	}
}

func TestNotificationDispatcher_IgnoredTransitions(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:            "ord-123",
			CustomerPhone: &phone,
		},
	}
	notif := &mockNotifier{}
	dispatcher := NewNotificationDispatcher(reader, notif, nil)

	// Transitions to PREPARING do not trigger customer notifications
	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "ACCEPTED", "PREPARING")

	if notif.dispatchCalls != 0 {
		t.Fatalf("expected 0 dispatch calls for intermediate kitchen status PREPARING, got %d", notif.dispatchCalls)
	}
}

func TestNotificationDispatcher_ReadyForPickupTransition(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:                  "ord-123",
			OrderNumber:         "ORD-READY-1",
			CustomerName:        "Doni",
			CustomerPhone:       &phone,
			Status:              "READY_FOR_PICKUP",
			TotalAmount:         35000,
			PublicTrackingToken: "trk_ready_123",
		},
	}
	notif := &mockNotifier{}
	dispatcher := NewNotificationDispatcher(reader, notif, nil)

	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "PREPARING", "READY_FOR_PICKUP")

	if notif.dispatchCalls != 1 {
		t.Fatalf("expected 1 dispatch call on READY_FOR_PICKUP, got %d", notif.dispatchCalls)
	}
	if notif.lastType != notification.TypeCompleted {
		t.Fatalf("expected TypeCompleted, got %s", notif.lastType)
	}
}

func TestNotificationDispatcher_NotifyOrderCreated_SingleReceiptPolicy(t *testing.T) {
	phone := "+6281234567890"
	notif := &mockNotifier{}

	// Case 1: Order from WHATSAPP bot -> should suppress duplicate confirmation
	waReader := &mockOrderReader{
		detail: OrderDetail{
			ID:            "ord-wa-1",
			Source:        "WHATSAPP",
			CustomerPhone: &phone,
		},
	}
	waDispatcher := NewNotificationDispatcher(waReader, notif, nil)
	waDispatcher.NotifyOrderCreated(context.Background(), "ord-wa-1")

	if notif.dispatchCalls != 0 {
		t.Fatalf("expected 0 dispatch calls for WHATSAPP order confirmation (single receipt), got %d", notif.dispatchCalls)
	}

	// Case 2: Order from MANUAL / POS -> should dispatch WhatsApp confirmation
	manualReader := &mockOrderReader{
		detail: OrderDetail{
			ID:            "ord-man-1",
			Source:        "MANUAL",
			CustomerPhone: &phone,
		},
	}
	manualDispatcher := NewNotificationDispatcher(manualReader, notif, nil)
	manualDispatcher.NotifyOrderCreated(context.Background(), "ord-man-1")

	if notif.dispatchCalls != 1 {
		t.Fatalf("expected 1 dispatch call for MANUAL order confirmation, got %d", notif.dispatchCalls)
	}
	if notif.lastType != notification.TypeConfirmation {
		t.Fatalf("expected TypeConfirmation, got %s", notif.lastType)
	}
}

func TestNotificationDispatcher_NoCustomerPhone_NoDispatch(t *testing.T) {
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:            "ord-123",
			CustomerPhone: nil, // Cashier manual without phone
		},
	}
	notif := &mockNotifier{}
	dispatcher := NewNotificationDispatcher(reader, notif, nil)

	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "READY_FOR_PICKUP", "COMPLETED")

	if notif.dispatchCalls != 0 {
		t.Fatalf("expected 0 calls when customer phone is absent, got %d", notif.dispatchCalls)
	}
}

type mockTransitionStore struct {
	transitionFunc func(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error)
	calls          int
}

func (m *mockTransitionStore) Transition(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error) {
	m.calls++
	if m.transitionFunc != nil {
		return m.transitionFunc(ctx, orderID, in, key, hash, actorID, roleRequest)
	}
	return StatusResult{ID: orderID, Status: in.TargetStatus, Version: in.ExpectedVersion + 1}, true, nil
}

type mockDispatcher struct {
	transitionCalls int
	lastTarget      string
}

func (m *mockDispatcher) NotifyStatusTransition(ctx context.Context, orderID, fromStatus, toStatus string) {
	m.transitionCalls++
	m.lastTarget = toStatus
}

func (m *mockDispatcher) NotifyOrderCreated(ctx context.Context, orderID string) {}

func TestOrderService_Transition_CompletedTriggersNotification(t *testing.T) {
	transStore := &mockTransitionStore{}
	svc := NewService(nil)
	svc.transitions = transStore

	dispatcher := &mockDispatcher{}
	svc.SetNotificationDispatcher(dispatcher)

	res, isNew, err := svc.Transition(context.Background(), "00000000-0000-0000-0000-000000000001", TransitionInput{
		TargetStatus:    "COMPLETED",
		ExpectedVersion: 3,
	}, "key-123", "staff-1", "STAFF", "req-1")

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !isNew {
		t.Fatal("expected isNew=true")
	}
	if res.Status != "COMPLETED" {
		t.Fatalf("expected status COMPLETED, got %s", res.Status)
	}
	if dispatcher.transitionCalls != 1 {
		t.Fatalf("expected dispatcher called 1 time, got %d", dispatcher.transitionCalls)
	}
	if dispatcher.lastTarget != "COMPLETED" {
		t.Fatalf("expected target status COMPLETED, got %s", dispatcher.lastTarget)
	}
}

func TestOrderService_Transition_FailedCommitDoesNotTriggerNotification(t *testing.T) {
	transStore := &mockTransitionStore{
		transitionFunc: func(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error) {
			return StatusResult{}, false, ErrVersionConflict
		},
	}
	svc := NewService(nil)
	svc.transitions = transStore

	dispatcher := &mockDispatcher{}
	svc.SetNotificationDispatcher(dispatcher)

	_, _, err := svc.Transition(context.Background(), "00000000-0000-0000-0000-000000000001", TransitionInput{
		TargetStatus:    "COMPLETED",
		ExpectedVersion: 3,
	}, "key-123", "staff-1", "STAFF", "req-1")

	if !errors.Is(err, ErrVersionConflict) {
		t.Fatalf("expected ErrVersionConflict, got %v", err)
	}
	if dispatcher.transitionCalls != 0 {
		t.Fatalf("notification should NEVER trigger on failed transition commit! calls = %d", dispatcher.transitionCalls)
	}
}

func TestOrderService_Transition_GOWAFailureDoesNotRollbackOrderStatus(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:            "00000000-0000-0000-0000-000000000001",
			OrderNumber:   "ORD-ERR-1",
			CustomerPhone: &phone,
		},
	}
	// mockNotifier that returns a GOWA error
	notif := &mockNotifier{
		dispatchErr: errors.New("gowa 503 service unavailable"),
	}
	realDispatcher := NewNotificationDispatcher(reader, notif, nil)

	transStore := &mockTransitionStore{}
	svc := NewService(nil)
	svc.transitions = transStore
	svc.SetNotificationDispatcher(realDispatcher)

	// Even though GOWA fails, the order transition MUST return success and not fail or rollback
	res, isNew, err := svc.Transition(context.Background(), "00000000-0000-0000-0000-000000000001", TransitionInput{
		TargetStatus:    "COMPLETED",
		ExpectedVersion: 2,
	}, "key-gowa-err", "staff-1", "STAFF", "req-gowa-err")

	if err != nil {
		t.Fatalf("transition must not return error when GOWA fails, got: %v", err)
	}
	if !isNew {
		t.Fatal("expected isNew=true")
	}
	if res.Status != "COMPLETED" {
		t.Fatalf("expected order status to be COMPLETED, got %s", res.Status)
	}
	if notif.dispatchCalls != 1 {
		t.Fatalf("expected notifier to have been attempted, calls = %d", notif.dispatchCalls)
	}
}
