package payment

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"
)

type reconciliationGatewayStub struct {
	notification MidtransNotification
	err          error
	calls        int
}

func (g *reconciliationGatewayStub) GetStatus(context.Context, string) (MidtransNotification, error) {
	g.calls++
	return g.notification, g.err
}

type reconciliationStoreStub struct {
	candidate    ReconciliationCandidate
	applyResult  WebhookResult
	applyErr     error
	finishCalls  int
	failureCalls int
	failureCode  string
	failureAlert bool
}

func (s *reconciliationStoreStub) ClaimDueReconciliations(context.Context, int, time.Time, time.Duration) ([]ReconciliationCandidate, error) {
	return []ReconciliationCandidate{s.candidate}, nil
}
func (s *reconciliationStoreStub) ClaimReconciliation(context.Context, string, time.Time, time.Duration) (ReconciliationCandidate, error) {
	return s.candidate, nil
}
func (s *reconciliationStoreStub) ApplyMidtransWebhook(context.Context, MidtransNotification, string, string, *time.Time) (WebhookResult, error) {
	return s.applyResult, s.applyErr
}
func (s *reconciliationStoreStub) FinishReconciliation(context.Context, ReconciliationCandidate, string, bool, time.Time) error {
	s.finishCalls++
	return nil
}
func (s *reconciliationStoreStub) FailReconciliation(_ context.Context, _ ReconciliationCandidate, code, _ string, _ time.Time, _ int) (bool, error) {
	s.failureCalls++
	s.failureCode = code
	return s.failureAlert, nil
}

func reconciliationFixture(now time.Time) (ReconciliationCandidate, MidtransNotification) {
	candidate := ReconciliationCandidate{PaymentID: "payment-1", OrderID: "order-1", ProviderOrderID: "PH-payment-1", ProviderReference: "tx-1", Amount: 27500, Attempt: 1}
	notification := MidtransNotification{OrderID: "PH-payment-1", TransactionID: "tx-1", TransactionStatus: "settlement", StatusCode: "200", GrossAmount: "27500.00", PaymentType: "qris", Currency: "IDR", FraudStatus: "accept", SettlementTime: now.Format("2006-01-02 15:04:05")}
	return candidate, notification
}

func newTestReconciler(store ReconciliationStore, gateway MidtransStatusGateway, now time.Time) *Reconciler {
	return NewReconciler(ReconcilerConfig{Store: store, Gateway: gateway, Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), BaseDelay: time.Second, MaxDelay: time.Minute, MaxAttempts: 3, Now: func() time.Time { return now }})
}

func TestReconcilerAppliesVerifiedProviderStatus(t *testing.T) {
	now := time.Date(2026, 9, 5, 10, 0, 0, 0, time.UTC)
	candidate, notification := reconciliationFixture(now)
	store := &reconciliationStoreStub{candidate: candidate, applyResult: WebhookResult{Payment: Payment{ID: candidate.PaymentID, Status: "PAID"}, Applied: true}}
	gateway := &reconciliationGatewayStub{notification: notification}
	reconciler := newTestReconciler(store, gateway, now)

	result, err := reconciler.ReconcilePayment(context.Background(), candidate.PaymentID, "req-manual")
	if err != nil || result.Outcome != "success" || !result.Applied || store.finishCalls != 1 || store.failureCalls != 0 || gateway.calls != 1 {
		t.Fatalf("result=%+v finish=%d failures=%d calls=%d err=%v", result, store.finishCalls, store.failureCalls, gateway.calls, err)
	}
	metrics := reconciler.Metrics()
	if metrics.Claimed != 1 || metrics.Succeeded != 1 || metrics.Applied != 1 {
		t.Fatalf("metrics=%+v", metrics)
	}
}

func TestReconcilerScheduledBatchClaimsAndProcessesDuePayment(t *testing.T) {
	now := time.Date(2026, 9, 5, 10, 0, 0, 0, time.UTC)
	candidate, notification := reconciliationFixture(now)
	store := &reconciliationStoreStub{candidate: candidate, applyResult: WebhookResult{Payment: Payment{ID: candidate.PaymentID, Status: "PAID"}, Applied: true}}
	reconciler := newTestReconciler(store, &reconciliationGatewayStub{notification: notification}, now)
	count, err := reconciler.ProcessBatch(context.Background())
	if err != nil || count != 1 || store.finishCalls != 1 || reconciler.Metrics().Claimed != 1 {
		t.Fatalf("count=%d finish=%d metrics=%+v err=%v", count, store.finishCalls, reconciler.Metrics(), err)
	}
}

func TestReconcilerNeverExpiresFromLocalClockWithoutProviderEvidence(t *testing.T) {
	now := time.Date(2026, 9, 5, 10, 0, 0, 0, time.UTC)
	candidate, notification := reconciliationFixture(now)
	expired := now.Add(-time.Minute)
	candidate.ExpiresAt = &expired
	notification.TransactionStatus, notification.StatusCode = "pending", "201"
	store := &reconciliationStoreStub{candidate: candidate}
	reconciler := newTestReconciler(store, &reconciliationGatewayStub{notification: notification}, now)

	result, err := reconciler.ReconcilePayment(context.Background(), candidate.PaymentID, "req-expired-local")
	if err != nil || result.Outcome != "retry" || store.failureCode != "provider_pending_past_expiry" || store.finishCalls != 0 {
		t.Fatalf("result=%+v failure=%q finish=%d err=%v", result, store.failureCode, store.finishCalls, err)
	}
}

func TestReconcilerUnknownAndProviderFailuresAreBoundedAndMeasured(t *testing.T) {
	now := time.Date(2026, 9, 5, 10, 0, 0, 0, time.UTC)
	candidate, _ := reconciliationFixture(now)
	candidate.Attempt = 3
	candidate.FailureCount = 2
	store := &reconciliationStoreStub{candidate: candidate, failureAlert: true}
	reconciler := newTestReconciler(store, &reconciliationGatewayStub{err: &ProviderError{Kind: "authentication"}}, now)

	result, err := reconciler.ReconcilePayment(context.Background(), candidate.PaymentID, "req-auth")
	if err != nil || result.Outcome != "alert" || store.failureCode != "authentication" {
		t.Fatalf("result=%+v failure=%q err=%v", result, store.failureCode, err)
	}
	metrics := reconciler.Metrics()
	if metrics.AuthenticationFailed != 1 || metrics.Alerted != 1 || metrics.Succeeded != 0 {
		t.Fatalf("metrics=%+v", metrics)
	}
}

func TestReconcilerRejectsMismatchedResponseAndDeduplicates(t *testing.T) {
	now := time.Date(2026, 9, 5, 10, 0, 0, 0, time.UTC)
	candidate, notification := reconciliationFixture(now)
	notification.GrossAmount = "999.00"
	store := &reconciliationStoreStub{candidate: candidate}
	reconciler := newTestReconciler(store, &reconciliationGatewayStub{notification: notification}, now)
	if result, err := reconciler.ReconcilePayment(context.Background(), candidate.PaymentID, "req-bad"); err != nil || result.Outcome != "retry" || store.failureCode != "provider_payload_mismatch" {
		t.Fatalf("result=%+v failure=%q err=%v", result, store.failureCode, err)
	}
	if reconciler.Metrics().ValidationFailed != 1 {
		t.Fatalf("metrics=%+v", reconciler.Metrics())
	}

	candidate, notification = reconciliationFixture(now)
	store = &reconciliationStoreStub{candidate: candidate, applyResult: WebhookResult{Payment: Payment{ID: candidate.PaymentID, Status: "PAID"}, Duplicate: true}}
	reconciler = newTestReconciler(store, &reconciliationGatewayStub{notification: notification}, now)
	result, err := reconciler.ReconcilePayment(context.Background(), candidate.PaymentID, "req-duplicate")
	if err != nil || !result.Duplicate || reconciler.Metrics().Duplicate != 1 || store.finishCalls != 1 {
		t.Fatalf("result=%+v metrics=%+v finish=%d err=%v", result, reconciler.Metrics(), store.finishCalls, err)
	}
}

func TestSafeReconciliationErrorNeverLeaksProviderDetails(t *testing.T) {
	if got := safeReconciliationError(errors.New("secret provider response")); got != "provider_error" {
		t.Fatalf("got %q", got)
	}
	if got := safeReconciliationError(&ProviderError{Kind: "unknown-secret-kind"}); got != "provider_error" {
		t.Fatalf("got %q", got)
	}
}

func TestReconciliationBackoffIsExponentialAndBounded(t *testing.T) {
	reconciler := NewReconciler(ReconcilerConfig{BaseDelay: time.Second, MaxDelay: 5 * time.Second})
	if reconciler.retryDelay(1) != time.Second || reconciler.retryDelay(3) != 4*time.Second || reconciler.retryDelay(10) != 5*time.Second {
		t.Fatalf("unexpected delays: %s %s %s", reconciler.retryDelay(1), reconciler.retryDelay(3), reconciler.retryDelay(10))
	}
}
