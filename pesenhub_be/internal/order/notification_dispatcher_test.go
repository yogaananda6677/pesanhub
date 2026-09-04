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

	// Transitions to PREPARING or READY_FOR_PICKUP do not trigger customer notifications
	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "ACCEPTED", "PREPARING")
	dispatcher.NotifyStatusTransition(context.Background(), "ord-123", "PREPARING", "READY_FOR_PICKUP")

	if notif.dispatchCalls != 0 {
		t.Fatalf("expected 0 dispatch calls for intermediate kitchen statuses, got %d", notif.dispatchCalls)
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

func TestOrderService_Transition_WAHAFailureDoesNotRollbackOrderStatus(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		detail: OrderDetail{
			ID:            "00000000-0000-0000-0000-000000000001",
			OrderNumber:   "ORD-ERR-1",
			CustomerPhone: &phone,
		},
	}
	// mockNotifier that returns a WAHA error
	notif := &mockNotifier{
		dispatchErr: errors.New("waha 503 service unavailable"),
	}
	realDispatcher := NewNotificationDispatcher(reader, notif, nil)

	transStore := &mockTransitionStore{}
	svc := NewService(nil)
	svc.transitions = transStore
	svc.SetNotificationDispatcher(realDispatcher)

	// Even though WAHA fails, the order transition MUST return success and not fail or rollback
	res, isNew, err := svc.Transition(context.Background(), "00000000-0000-0000-0000-000000000001", TransitionInput{
		TargetStatus:    "COMPLETED",
		ExpectedVersion: 2,
	}, "key-waha-err", "staff-1", "STAFF", "req-waha-err")

	if err != nil {
		t.Fatalf("transition must not return error when WAHA fails, got: %v", err)
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
