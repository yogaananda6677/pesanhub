package payment

import (
	"context"
	"errors"
	"log/slog"
	"math"
	"sync"
	"sync/atomic"
	"time"
)

type ReconciliationStore interface {
	ClaimDueReconciliations(context.Context, int, time.Time, time.Duration) ([]ReconciliationCandidate, error)
	ClaimReconciliation(context.Context, string, time.Time, time.Duration) (ReconciliationCandidate, error)
	ApplyMidtransWebhook(context.Context, MidtransNotification, string, string, *time.Time) (WebhookResult, error)
	FinishReconciliation(context.Context, ReconciliationCandidate, string, bool, time.Time) error
	FailReconciliation(context.Context, ReconciliationCandidate, string, string, time.Time, int) (bool, error)
}

type ReconciliationMetrics struct {
	Claimed, Succeeded, Applied, Duplicate, Retried, Alerted, Timeout, AuthenticationFailed, ValidationFailed, StoreFailed uint64
}

type reconciliationCounters struct {
	claimed, succeeded, applied, duplicate, retried, alerted, timeout, authenticationFailed, validationFailed, storeFailed atomic.Uint64
}

type ReconcilerConfig struct {
	Store          ReconciliationStore
	Gateway        MidtransStatusGateway
	Logger         *slog.Logger
	BatchSize      int
	PollInterval   time.Duration
	BaseDelay      time.Duration
	MaxDelay       time.Duration
	StaleThreshold time.Duration
	MaxAttempts    int
	Now            func() time.Time
}

type Reconciler struct {
	store          ReconciliationStore
	gateway        MidtransStatusGateway
	logger         *slog.Logger
	batchSize      int
	pollInterval   time.Duration
	baseDelay      time.Duration
	maxDelay       time.Duration
	staleThreshold time.Duration
	maxAttempts    int
	now            func() time.Time
	counters       reconciliationCounters
	mu             sync.Mutex
	running        bool
}

func NewReconciler(cfg ReconcilerConfig) *Reconciler {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if cfg.BatchSize <= 0 {
		cfg.BatchSize = 10
	}
	if cfg.PollInterval <= 0 {
		cfg.PollInterval = 30 * time.Second
	}
	if cfg.BaseDelay <= 0 {
		cfg.BaseDelay = 30 * time.Second
	}
	if cfg.MaxDelay <= 0 {
		cfg.MaxDelay = 15 * time.Minute
	}
	if cfg.StaleThreshold <= 0 {
		cfg.StaleThreshold = 2 * time.Minute
	}
	if cfg.MaxAttempts <= 0 {
		cfg.MaxAttempts = 5
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	return &Reconciler{store: cfg.Store, gateway: cfg.Gateway, logger: cfg.Logger, batchSize: cfg.BatchSize, pollInterval: cfg.PollInterval, baseDelay: cfg.BaseDelay, maxDelay: cfg.MaxDelay, staleThreshold: cfg.StaleThreshold, maxAttempts: cfg.MaxAttempts, now: cfg.Now}
}

func (r *Reconciler) Metrics() ReconciliationMetrics {
	return ReconciliationMetrics{Claimed: r.counters.claimed.Load(), Succeeded: r.counters.succeeded.Load(), Applied: r.counters.applied.Load(), Duplicate: r.counters.duplicate.Load(), Retried: r.counters.retried.Load(), Alerted: r.counters.alerted.Load(), Timeout: r.counters.timeout.Load(), AuthenticationFailed: r.counters.authenticationFailed.Load(), ValidationFailed: r.counters.validationFailed.Load(), StoreFailed: r.counters.storeFailed.Load()}
}

func (r *Reconciler) Start(ctx context.Context) {
	r.mu.Lock()
	if r.running {
		r.mu.Unlock()
		return
	}
	r.running = true
	r.mu.Unlock()
	defer func() { r.mu.Lock(); r.running = false; r.mu.Unlock() }()
	ticker := time.NewTicker(r.pollInterval)
	defer ticker.Stop()
	r.processDue(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			r.processDue(ctx)
		}
	}
}

func (r *Reconciler) ProcessBatch(ctx context.Context) (int, error) {
	if r.store == nil || r.gateway == nil {
		return 0, nil
	}
	candidates, err := r.store.ClaimDueReconciliations(ctx, r.batchSize, r.now().UTC(), r.staleThreshold)
	if err != nil {
		return 0, err
	}
	r.counters.claimed.Add(uint64(len(candidates)))
	for _, candidate := range candidates {
		if _, err := r.reconcile(ctx, candidate, "scheduled"); err != nil {
			r.logger.Error("Midtrans payment reconciliation persistence failed", "outcome", "store_failed", "payment_id", candidate.PaymentID, "attempt", candidate.Attempt)
		}
	}
	return len(candidates), nil
}

func (r *Reconciler) ReconcilePayment(ctx context.Context, paymentID, requestID string) (ReconciliationResult, error) {
	if r.store == nil || r.gateway == nil {
		return ReconciliationResult{}, ErrMidtransNotReady
	}
	candidate, err := r.store.ClaimReconciliation(ctx, paymentID, r.now().UTC(), r.staleThreshold)
	if err != nil {
		return ReconciliationResult{}, err
	}
	r.counters.claimed.Add(1)
	return r.reconcile(ctx, candidate, requestID)
}

func (r *Reconciler) processDue(ctx context.Context) {
	for {
		count, err := r.ProcessBatch(ctx)
		if err != nil {
			r.counters.storeFailed.Add(1)
			r.logger.Error("Midtrans reconciliation batch failed", "outcome", "store_failed")
			return
		}
		if count == 0 || count < r.batchSize {
			return
		}
	}
}

func (r *Reconciler) reconcile(ctx context.Context, candidate ReconciliationCandidate, requestID string) (ReconciliationResult, error) {
	notification, err := r.gateway.GetStatus(ctx, candidate.ProviderOrderID)
	if err != nil {
		code := safeReconciliationError(err)
		switch code {
		case "timeout":
			r.counters.timeout.Add(1)
		case "authentication":
			r.counters.authenticationFailed.Add(1)
		case "invalid_response":
			r.counters.validationFailed.Add(1)
		}
		return r.fail(ctx, candidate, code, requestID)
	}
	if notification.OrderID != candidate.ProviderOrderID || (candidate.ProviderReference != "" && notification.TransactionID != candidate.ProviderReference) {
		r.counters.validationFailed.Add(1)
		return r.fail(ctx, candidate, "provider_identity_mismatch", requestID)
	}
	amount, amountErr := parseIDRAmount(notification.GrossAmount)
	if amountErr != nil || amount != candidate.Amount || notification.PaymentType != "qris" || notification.Currency != "IDR" {
		r.counters.validationFailed.Add(1)
		return r.fail(ctx, candidate, "provider_payload_mismatch", requestID)
	}
	target, err := mapMidtransStatus(notification)
	if err != nil {
		r.counters.validationFailed.Add(1)
		return r.fail(ctx, candidate, "provider_status_invalid", requestID)
	}
	if target == "PENDING_PAYMENT" && candidate.ExpiresAt != nil && !candidate.ExpiresAt.After(r.now().UTC()) {
		return r.fail(ctx, candidate, "provider_pending_past_expiry", requestID)
	}
	occurredAt, occurredAtErr := midtransOccurredAt(notification)
	if occurredAtErr != nil {
		r.counters.validationFailed.Add(1)
		return r.fail(ctx, candidate, "provider_timestamp_invalid", requestID)
	}
	result, err := r.store.ApplyMidtransWebhook(ctx, notification, midtransEventID(notification), requestID, occurredAt)
	if err != nil {
		r.counters.storeFailed.Add(1)
		return r.fail(ctx, candidate, safeReconciliationStoreError(err), requestID)
	}
	terminal := result.Payment.Status != "UNPAID" && result.Payment.Status != "PENDING_PAYMENT"
	nextAt := r.now().UTC().Add(2 * time.Minute)
	if candidate.ExpiresAt != nil && candidate.ExpiresAt.Before(nextAt) && candidate.ExpiresAt.After(r.now().UTC()) {
		nextAt = *candidate.ExpiresAt
	}
	if err := r.store.FinishReconciliation(ctx, candidate, notification.TransactionStatus, terminal, nextAt); err != nil {
		r.counters.storeFailed.Add(1)
		return ReconciliationResult{}, err
	}
	r.counters.succeeded.Add(1)
	if result.Applied {
		r.counters.applied.Add(1)
	}
	if result.Duplicate {
		r.counters.duplicate.Add(1)
	}
	r.logger.Info("Midtrans payment reconciled", "outcome", "success", "payment_id", candidate.PaymentID, "provider_status", notification.TransactionStatus, "applied", result.Applied, "duplicate", result.Duplicate, "attempt", candidate.Attempt)
	return ReconciliationResult{Payment: &result.Payment, Applied: result.Applied, Duplicate: result.Duplicate, Outcome: "success", Attempt: candidate.Attempt}, nil
}

func (r *Reconciler) fail(ctx context.Context, candidate ReconciliationCandidate, code, requestID string) (ReconciliationResult, error) {
	next := r.now().UTC().Add(r.retryDelay(candidate.FailureCount + 1))
	alert, err := r.store.FailReconciliation(ctx, candidate, code, requestID, next, r.maxAttempts)
	if err != nil {
		r.counters.storeFailed.Add(1)
		return ReconciliationResult{}, err
	}
	if alert {
		r.counters.alerted.Add(1)
		r.logger.Warn("Midtrans payment reconciliation needs operator attention", "outcome", "alert", "payment_id", candidate.PaymentID, "error_code", code, "attempt", candidate.Attempt)
		return ReconciliationResult{Outcome: "alert", Attempt: candidate.Attempt}, nil
	}
	r.counters.retried.Add(1)
	r.logger.Warn("Midtrans payment reconciliation scheduled for retry", "outcome", "retry", "payment_id", candidate.PaymentID, "error_code", code, "attempt", candidate.Attempt)
	return ReconciliationResult{Outcome: "retry", Attempt: candidate.Attempt}, nil
}

func (r *Reconciler) retryDelay(attempt int) time.Duration {
	exponent := math.Max(0, math.Min(float64(attempt-1), 10))
	delay := time.Duration(float64(r.baseDelay) * math.Pow(2, exponent))
	if delay > r.maxDelay {
		return r.maxDelay
	}
	return delay
}

func safeReconciliationError(err error) string {
	var providerErr *ProviderError
	if !errors.As(err, &providerErr) {
		return "provider_error"
	}
	switch providerErr.Kind {
	case "timeout", "network", "server", "rate_limited", "not_found", "authentication", "rejected", "invalid_response":
		return providerErr.Kind
	default:
		return "provider_error"
	}
}

func safeReconciliationStoreError(err error) string {
	switch {
	case errors.Is(err, ErrPaymentNotFound):
		return "payment_not_found"
	case errors.Is(err, ErrWebhookAmount):
		return "provider_payload_mismatch"
	case errors.Is(err, ErrWebhookReference):
		return "provider_identity_mismatch"
	default:
		return "store_error"
	}
}
