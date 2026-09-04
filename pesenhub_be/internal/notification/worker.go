package notification

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"pesenhub/backend/internal/gowa"
)

// WorkerConfig holds configuration options for OutboxWorker.
type WorkerConfig struct {
	Store          Store
	Sender         gowa.Sender
	Logger         *slog.Logger
	BatchSize      int
	PollInterval   time.Duration
	BaseDelay      time.Duration
	MaxDelay       time.Duration
	StaleThreshold time.Duration
}

// OutboxWorker processes pending and retrying notification records reliably in background.
type OutboxWorker struct {
	store          Store
	sender         gowa.Sender
	logger         *slog.Logger
	batchSize      int
	pollInterval   time.Duration
	baseDelay      time.Duration
	maxDelay       time.Duration
	staleThreshold time.Duration
	notifyCh       chan struct{}
	mu             sync.Mutex
	running        bool
}

// NewOutboxWorker constructs a new OutboxWorker with default or configured values.
func NewOutboxWorker(cfg WorkerConfig) *OutboxWorker {
	logger := cfg.Logger
	if logger == nil {
		logger = slog.Default()
	}
	batchSize := cfg.BatchSize
	if batchSize <= 0 {
		batchSize = 10
	}
	pollInterval := cfg.PollInterval
	if pollInterval <= 0 {
		pollInterval = 1 * time.Second
	}
	baseDelay := cfg.BaseDelay
	if baseDelay <= 0 {
		baseDelay = 1 * time.Second
	}
	maxDelay := cfg.MaxDelay
	if maxDelay <= 0 {
		maxDelay = 60 * time.Second
	}
	staleThreshold := cfg.StaleThreshold
	if staleThreshold <= 0 {
		staleThreshold = 2 * time.Minute
	}

	return &OutboxWorker{
		store:          cfg.Store,
		sender:         cfg.Sender,
		logger:         logger,
		batchSize:      batchSize,
		pollInterval:   pollInterval,
		baseDelay:      baseDelay,
		maxDelay:       maxDelay,
		staleThreshold: staleThreshold,
		notifyCh:       make(chan struct{}, 100),
	}
}

// Notify triggers an immediate outbox drain without waiting for the next ticker interval.
func (w *OutboxWorker) Notify() {
	if w == nil {
		return
	}
	select {
	case w.notifyCh <- struct{}{}:
	default:
	}
}

// Start begins the background processing loop until ctx is canceled.
func (w *OutboxWorker) Start(ctx context.Context, overrideInterval ...time.Duration) {
	w.mu.Lock()
	if w.running {
		w.mu.Unlock()
		return
	}
	w.running = true
	w.mu.Unlock()

	interval := w.pollInterval
	if len(overrideInterval) > 0 && overrideInterval[0] > 0 {
		interval = overrideInterval[0]
	}

	// Startup recovery: recover any in-flight jobs left in PROCESSING by previous crash
	if w.store != nil {
		recovered, err := w.store.RecoverStaleProcessing(ctx, 0)
		if err != nil {
			w.logger.Error("failed to recover in-flight processing records on startup", "error", err)
		} else if recovered > 0 {
			w.logger.Info("recovered in-flight processing records on startup", "count", recovered)
		}
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	staleCheckTicker := time.NewTicker(30 * time.Second)
	defer staleCheckTicker.Stop()

	for {
		select {
		case <-ctx.Done():
			w.mu.Lock()
			w.running = false
			w.mu.Unlock()
			return
		case <-w.notifyCh:
			w.drainPending(ctx)
		case <-ticker.C:
			w.drainPending(ctx)
		case <-staleCheckTicker.C:
			if w.store != nil {
				_, _ = w.store.RecoverStaleProcessing(ctx, w.staleThreshold)
			}
		}
	}
}

func (w *OutboxWorker) drainPending(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		count, err := w.ProcessBatch(ctx)
		if err != nil {
			w.logger.Error("outbox worker batch error", "error", err)
			return
		}
		if count == 0 {
			return
		}
	}
}

// ProcessBatch claims and processes up to batchSize records.
// Returns number of records claimed, and any fatal claiming error.
func (w *OutboxWorker) ProcessBatch(ctx context.Context) (int, error) {
	if w == nil || w.store == nil {
		return 0, nil
	}

	records, err := w.store.ClaimBatchForProcessing(ctx, w.batchSize)
	if err != nil {
		return 0, err
	}
	if len(records) == 0 {
		return 0, nil
	}

	for _, rec := range records {
		w.processRecord(ctx, rec)
	}

	return len(records), nil
}

func (w *OutboxWorker) processRecord(ctx context.Context, rec *NotificationRecord) {
	maskedPhone := gowa.MaskPhone(rec.CustomerPhone)

	// 1. Opt-Out Guard Re-evaluation
	optedOut, err := w.store.IsOptedOut(ctx, rec.CustomerPhone)
	if err != nil {
		w.logger.Error("error checking opt-out status during outbox retry", "error", err, "phone", maskedPhone)
	} else if optedOut {
		_ = w.store.MarkSuppressed(ctx, rec.ID, SuppressCustomerOptedOut)
		w.logger.Info("notification suppressed during outbox retry: customer opted out",
			"order_id", rec.OrderID,
			"masked_phone", maskedPhone,
			"type", rec.NotificationType,
		)
		return
	}

	// 2. Conversation Paused & Handoff Guard Re-evaluation
	isPaused, pauseReason, err := w.store.IsConversationPaused(ctx, rec.CustomerPhone)
	if err != nil {
		w.logger.Error("error checking conversation pause status during outbox retry", "error", err, "phone", maskedPhone)
	} else if isPaused {
		_ = w.store.MarkSuppressed(ctx, rec.ID, pauseReason)
		w.logger.Info("notification suppressed during outbox retry: conversation paused or handoff active",
			"order_id", rec.OrderID,
			"masked_phone", maskedPhone,
			"type", rec.NotificationType,
			"reason", pauseReason,
		)
		return
	}

	// 3. Dispatch to GOWA
	if w.sender == nil {
		safeErr := "sender_not_configured"
		_ = w.store.MarkDeadLetter(ctx, rec.ID, CategoryPermanentValidation, safeErr)
		return
	}

	providerMsgID, sendErr := w.sender.SendMessage(ctx, rec.CustomerPhone, rec.MessageText)
	if sendErr == nil {
		// Success ACK closes outbox
		_ = w.store.MarkSent(ctx, rec.ID, providerMsgID)
		w.logger.Info("outbox successfully dispatched WhatsApp notification",
			"order_id", rec.OrderID,
			"masked_phone", maskedPhone,
			"type", rec.NotificationType,
			"provider_message_id", providerMsgID,
			"attempts", rec.Attempts+1,
		)
		return
	}

	// Failure handling: classify error and decide retry vs dead-letter
	category, retryable := ClassifyError(sendErr)
	safeErr := SanitizeError(sendErr)

	if !retryable {
		_ = w.store.MarkDeadLetter(ctx, rec.ID, category, safeErr)
		w.logger.Warn("outbox permanent failure: moved to dead-letter",
			"order_id", rec.OrderID,
			"masked_phone", maskedPhone,
			"category", category,
			"error", safeErr,
		)
		return
	}

	// Retryable failure: check max attempts
	nextAttempt := rec.Attempts + 1
	maxAttempts := rec.MaxAttempts
	if maxAttempts <= 0 {
		maxAttempts = 5
	}

	if nextAttempt >= maxAttempts {
		deadLetterMsg := "max attempts reached: " + safeErr
		_ = w.store.MarkDeadLetter(ctx, rec.ID, CategoryMaxAttemptsExceeded, deadLetterMsg)
		w.logger.Warn("outbox max attempts exceeded: moved to dead-letter",
			"order_id", rec.OrderID,
			"masked_phone", maskedPhone,
			"attempts", nextAttempt,
			"max_attempts", maxAttempts,
			"category", CategoryMaxAttemptsExceeded,
			"error", deadLetterMsg,
		)
		return
	}

	// Schedule retry with exponential backoff while preserving idempotency key
	delay := CalculateBackoff(nextAttempt, w.baseDelay, w.maxDelay)
	nextRetry := time.Now().UTC().Add(delay)
	_ = w.store.ScheduleRetry(ctx, rec.ID, nextRetry, category, safeErr)
	w.logger.Info("outbox transient failure: scheduled retry",
		"order_id", rec.OrderID,
		"masked_phone", maskedPhone,
		"attempt", nextAttempt,
		"backoff_delay", delay.String(),
		"next_retry_at", nextRetry.Format(time.RFC3339),
		"category", category,
	)
}

var (
	ErrWorkerAlreadyRunning = errors.New("worker already running")
)
