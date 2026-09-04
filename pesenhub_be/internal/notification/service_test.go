package notification

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
)

type mockSender struct {
	sendFunc func(ctx context.Context, toPhone, text string) (string, error)
	calls    int64
}

func (m *mockSender) SendMessage(ctx context.Context, toPhone, text string) (string, error) {
	atomic.AddInt64(&m.calls, 1)
	if m.sendFunc != nil {
		return m.sendFunc(ctx, toPhone, text)
	}
	return "wamid.mock.123", nil
}

func sampleData() OrderNotificationData {
	return OrderNotificationData{
		OrderID:       "ord-001",
		OrderNumber:   "ORD-20260904-001",
		CustomerName:  "Budi Santoso",
		CustomerPhone: "+6281234567890",
		TotalAmount:   25000,
		TrackingToken: "trk_abc_123",
		Items: []OrderItemSummary{
			{Name: "Nasi Goreng", Quantity: 1, UnitPrice: 25000, LineTotal: 25000},
		},
	}
}

func TestDispatch_Success(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{
		sendFunc: func(ctx context.Context, toPhone, text string) (string, error) {
			return "wamid.success.999", nil
		},
	}
	svc := NewService(Config{
		Store:  store,
		Sender: sender,
	})

	res, err := svc.NotifyConfirmation(context.Background(), sampleData())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Status != StatusSent {
		t.Fatalf("expected StatusSent, got %s", res.Status)
	}
	if res.ProviderMessageID != "wamid.success.999" {
		t.Fatalf("expected wamid.success.999, got %s", res.ProviderMessageID)
	}
	if sender.calls != 1 {
		t.Fatalf("expected 1 call to sender, got %d", sender.calls)
	}

	// Verify in store
	key := "order:ord-001:type:CONFIRMATION:v:v1"
	rec, err := store.GetByIdempotencyKey(context.Background(), key)
	if err != nil {
		t.Fatalf("record not found in store: %v", err)
	}
	if rec.Status != StatusSent {
		t.Errorf("store status = %s, expected %s", rec.Status, StatusSent)
	}
}

func TestDispatch_AtMostOnceDeduplication(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{}
	svc := NewService(Config{
		Store:  store,
		Sender: sender,
	})

	// First call -> sends
	res1, err := svc.NotifyConfirmation(context.Background(), sampleData())
	if err != nil {
		t.Fatalf("first call error: %v", err)
	}
	if res1.Status != StatusSent || res1.IsDuplicate {
		t.Fatalf("expected first call to be non-duplicate sent, got %+v", res1)
	}
	if sender.calls != 1 {
		t.Fatalf("expected sender calls = 1, got %d", sender.calls)
	}

	// Second call (replay event) -> deduplicated, does NOT call sender
	res2, err := svc.NotifyConfirmation(context.Background(), sampleData())
	if err != nil {
		t.Fatalf("second call error: %v", err)
	}
	if !res2.IsDuplicate {
		t.Fatal("expected second call to have IsDuplicate = true")
	}
	if res2.Status != StatusSent {
		t.Fatalf("expected status = StatusSent, got %s", res2.Status)
	}
	if sender.calls != 1 {
		t.Fatalf("sender was called again! expected calls = 1, got %d", sender.calls)
	}
}

func TestDispatch_OptOutGuard(t *testing.T) {
	store := NewMemoryStore()
	_ = store.SetOptOut(context.Background(), "+6281234567890", "user requested STOP")
	sender := &mockSender{}
	svc := NewService(Config{
		Store:  store,
		Sender: sender,
	})

	res, err := svc.NotifyCompleted(context.Background(), sampleData())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Status != StatusSuppressed {
		t.Fatalf("expected StatusSuppressed, got %s", res.Status)
	}
	if res.SuppressReason != string(SuppressCustomerOptedOut) {
		t.Fatalf("expected suppress reason %s, got %s", SuppressCustomerOptedOut, res.SuppressReason)
	}
	if sender.calls != 0 {
		t.Fatalf("sender should not be called for opted out customer! calls = %d", sender.calls)
	}
}

func TestDispatch_ConversationPausedGuard(t *testing.T) {
	store := NewMemoryStore()
	store.SetPausedPhone("+6281234567890", true)
	sender := &mockSender{}
	svc := NewService(Config{
		Store:  store,
		Sender: sender,
	})

	res, err := svc.NotifyAccepted(context.Background(), sampleData())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Status != StatusSuppressed {
		t.Fatalf("expected StatusSuppressed, got %s", res.Status)
	}
	if res.SuppressReason != string(SuppressConversationPaused) {
		t.Fatalf("expected suppress reason %s, got %s", SuppressConversationPaused, res.SuppressReason)
	}
	if sender.calls != 0 {
		t.Fatalf("sender should not be called when conversation is paused! calls = %d", sender.calls)
	}
}

func TestDispatch_HandoffActiveGuard(t *testing.T) {
	store := NewMemoryStore()
	store.SetHandoffPhone("+6281234567890", true)
	sender := &mockSender{}
	svc := NewService(Config{
		Store:  store,
		Sender: sender,
	})

	res, err := svc.NotifyCompleted(context.Background(), sampleData())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Status != StatusSuppressed {
		t.Fatalf("expected StatusSuppressed, got %s", res.Status)
	}
	if res.SuppressReason != string(SuppressHandoffActive) {
		t.Fatalf("expected suppress reason %s, got %s", SuppressHandoffActive, res.SuppressReason)
	}
	if sender.calls != 0 {
		t.Fatalf("sender should not be called when handoff is active! calls = %d", sender.calls)
	}
}

func TestDispatch_GOWAFailure_DoesNotFailFatal(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{
		sendFunc: func(ctx context.Context, toPhone, text string) (string, error) {
			return "", errors.New("gowa gateway timeout 504")
		},
	}
	svc := NewService(Config{
		Store:  store,
		Sender: sender,
	})

	// Must NOT return a fatal error that would break domain callers
	res, err := svc.NotifyCompleted(context.Background(), sampleData())
	if err != nil {
		t.Fatalf("dispatch should return non-fatal result on GOWA failure, but returned err: %v", err)
	}
	if res.Status != StatusFailed {
		t.Fatalf("expected StatusFailed, got %s", res.Status)
	}
	if res.Error == nil || res.Error.Error() != "gowa gateway timeout 504" {
		t.Fatalf("expected error message preserved in result, got %v", res.Error)
	}

	// Verify store marked as failed
	key := "order:ord-001:type:COMPLETED:v:v1"
	rec, err := store.GetByIdempotencyKey(context.Background(), key)
	if err != nil {
		t.Fatalf("record not found in store: %v", err)
	}
	if rec.Status != StatusFailed {
		t.Errorf("store status = %s, expected %s", rec.Status, StatusFailed)
	}
}

func TestDispatch_InvalidPhone_FailsCleanly(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{}
	svc := NewService(Config{
		Store:  store,
		Sender: sender,
	})

	data := sampleData()
	data.CustomerPhone = "not-a-phone"

	res, err := svc.NotifyCompleted(context.Background(), data)
	if err != nil {
		t.Fatalf("expected no fatal error, got %v", err)
	}
	if res.Status != StatusFailed {
		t.Fatalf("expected StatusFailed, got %s", res.Status)
	}
	if !errors.Is(res.Error, ErrInvalidRecipient) {
		t.Fatalf("expected ErrInvalidRecipient, got %v", res.Error)
	}
	if sender.calls != 0 {
		t.Fatalf("sender should not be called for invalid phone")
	}
}
