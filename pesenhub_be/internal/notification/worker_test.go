package notification

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"pesenhub/backend/internal/waha"
)

func TestCalculateBackoff(t *testing.T) {
	base := 1 * time.Second
	maxDelay := 60 * time.Second

	tests := []struct {
		attempt  int
		expected time.Duration
	}{
		{attempt: 0, expected: 1 * time.Second},
		{attempt: 1, expected: 1 * time.Second},
		{attempt: 2, expected: 2 * time.Second},
		{attempt: 3, expected: 4 * time.Second},
		{attempt: 4, expected: 8 * time.Second},
		{attempt: 5, expected: 16 * time.Second},
		{attempt: 6, expected: 32 * time.Second},
		{attempt: 7, expected: 60 * time.Second},  // capped at maxDelay (64s -> 60s)
		{attempt: 10, expected: 60 * time.Second}, // capped
		{attempt: 50, expected: 60 * time.Second}, // no overflow
	}

	for _, tc := range tests {
		got := CalculateBackoff(tc.attempt, base, maxDelay)
		if got != tc.expected {
			t.Errorf("attempt %d: expected %v, got %v", tc.attempt, tc.expected, got)
		}
	}
}

func TestClassifyError(t *testing.T) {
	tests := []struct {
		err         error
		expectedCat ErrorCategory
		expectedRtr bool
	}{
		{err: waha.ErrValidation, expectedCat: CategoryPermanentValidation, expectedRtr: false},
		{err: ErrInvalidRecipient, expectedCat: CategoryPermanentValidation, expectedRtr: false},
		{err: errors.New("validation failed for phone"), expectedCat: CategoryPermanentValidation, expectedRtr: false},
		{err: errors.New("HTTP status 400 bad request"), expectedCat: CategoryPermanentValidation, expectedRtr: false},
		{err: waha.ErrAuthentication, expectedCat: CategoryPermanentAuth, expectedRtr: false},
		{err: errors.New("status 401 unauthorized"), expectedCat: CategoryPermanentAuth, expectedRtr: false},
		{err: waha.ErrTimeout, expectedCat: CategoryTransientTimeout, expectedRtr: true},
		{err: context.DeadlineExceeded, expectedCat: CategoryTransientTimeout, expectedRtr: true},
		{err: errors.New("gateway timeout"), expectedCat: CategoryTransientTimeout, expectedRtr: true},
		{err: waha.ErrSessionNotReady, expectedCat: CategorySessionNotReady, expectedRtr: true},
		{err: waha.ErrSessionAbsent, expectedCat: CategorySessionNotReady, expectedRtr: true},
		{err: waha.ErrProvider, expectedCat: CategoryTransientProvider, expectedRtr: true},
		{err: errors.New("dial tcp: connection refused"), expectedCat: CategoryTransientNetwork, expectedRtr: true},
		{err: errors.New("something totally unexpected"), expectedCat: CategoryUnknown, expectedRtr: true},
	}

	for _, tc := range tests {
		cat, retryable := ClassifyError(tc.err)
		if cat != tc.expectedCat || retryable != tc.expectedRtr {
			t.Errorf("for error %v: got (%s, %v), expected (%s, %v)", tc.err, cat, retryable, tc.expectedCat, tc.expectedRtr)
		}
	}
}

func TestSanitizeError(t *testing.T) {
	// Secret scrubbing
	errWithSecret := errors.New("request failed: api-key=secret_12345_token, status 401")
	sanitized := SanitizeError(errWithSecret)
	if strings.Contains(sanitized, "secret_12345_token") {
		t.Errorf("secret not scrubbed: %s", sanitized)
	}
	if !strings.Contains(sanitized, "[REDACTED]") {
		t.Errorf("expected [REDACTED], got: %s", sanitized)
	}

	// Phone number masking
	errWithPhone := errors.New("failed to send text to +6281234567890: network error")
	sanitizedPhone := SanitizeError(errWithPhone)
	if strings.Contains(sanitizedPhone, "+6281234567890") {
		t.Errorf("phone not masked: %s", sanitizedPhone)
	}
	if !strings.Contains(sanitizedPhone, "+6281****7890") {
		t.Errorf("expected masked phone +6281****7890, got: %s", sanitizedPhone)
	}

	// Long error truncation
	longText := strings.Repeat("error detail ", 30)
	sanitizedLong := SanitizeError(errors.New(longText))
	if len(sanitizedLong) > 255 {
		t.Errorf("length exceeds 255 chars: %d", len(sanitizedLong))
	}
	if !strings.HasSuffix(sanitizedLong, "...") {
		t.Errorf("expected suffix ..., got: %s", sanitizedLong)
	}
}

func TestWorker_TransientFailure_SchedulesRetry(t *testing.T) {
	store := NewMemoryStore()
	var callCount int64
	sender := &mockSender{
		sendFunc: func(ctx context.Context, toPhone, text string) (string, error) {
			atomic.AddInt64(&callCount, 1)
			return "", waha.ErrTimeout
		},
	}

	worker := NewOutboxWorker(WorkerConfig{
		Store:     store,
		Sender:    sender,
		BaseDelay: 2 * time.Second,
		MaxDelay:  30 * time.Second,
	})

	// Create pending notification
	rec := &NotificationRecord{
		OrderID:          "ord-retry-1",
		CustomerPhone:    "+6281234567890",
		NotificationType: TypeConfirmation,
		TemplateVersion:  "v1",
		IdempotencyKey:   "order:ord-retry-1:type:CONFIRMATION:v:v1",
		MessageText:      "Halo test retry",
		MaxAttempts:      3,
	}
	created, _, err := store.CreatePending(context.Background(), rec)
	if err != nil {
		t.Fatal(err)
	}

	// First run: attempts = 0 -> fails with timeout -> attempts becomes 1, next_retry_at in future
	count, err := worker.ProcessBatch(context.Background())
	if err != nil {
		t.Fatalf("ProcessBatch failed: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected 1 record processed, got %d", count)
	}

	loaded, err := store.GetByIdempotencyKey(context.Background(), rec.IdempotencyKey)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Status != StatusFailed {
		t.Fatalf("expected status FAILED, got %s", loaded.Status)
	}
	if loaded.Attempts != 1 {
		t.Fatalf("expected attempts = 1, got %d", loaded.Attempts)
	}
	if loaded.NextRetryAt == nil || loaded.NextRetryAt.Before(time.Now().UTC()) {
		t.Fatalf("expected next_retry_at scheduled in the future, got %v", loaded.NextRetryAt)
	}
	if loaded.ErrorCategory == nil || *loaded.ErrorCategory != CategoryTransientTimeout {
		t.Fatalf("expected category %s, got %v", CategoryTransientTimeout, loaded.ErrorCategory)
	}
	if loaded.IdempotencyKey != created.IdempotencyKey {
		t.Fatalf("idempotency key mutated! expected %s, got %s", created.IdempotencyKey, loaded.IdempotencyKey)
	}

	// Second immediate run: record is NOT yet eligible because next_retry_at is in future
	count2, err := worker.ProcessBatch(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if count2 != 0 {
		t.Fatalf("expected 0 records claimed before next_retry_at, got %d", count2)
	}
}

func TestWorker_SuccessACK_ClosesOutbox(t *testing.T) {
	store := NewMemoryStore()
	var sendCalls int64
	sender := &mockSender{
		sendFunc: func(ctx context.Context, toPhone, text string) (string, error) {
			atomic.AddInt64(&sendCalls, 1)
			return "wamid.success.101", nil
		},
	}

	worker := NewOutboxWorker(WorkerConfig{
		Store:  store,
		Sender: sender,
	})

	rec := &NotificationRecord{
		OrderID:          "ord-ack-1",
		CustomerPhone:    "+6281234567890",
		NotificationType: TypeConfirmation,
		TemplateVersion:  "v1",
		IdempotencyKey:   "order:ord-ack-1:type:CONFIRMATION:v:v1",
		MessageText:      "Halo test ack",
	}
	_, _, err := store.CreatePending(context.Background(), rec)
	if err != nil {
		t.Fatal(err)
	}

	// First batch -> succeeds
	count, err := worker.ProcessBatch(context.Background())
	if err != nil || count != 1 {
		t.Fatalf("expected 1 processed, got count=%d, err=%v", count, err)
	}

	loaded, err := store.GetByIdempotencyKey(context.Background(), rec.IdempotencyKey)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Status != StatusSent {
		t.Fatalf("expected status SENT, got %s", loaded.Status)
	}
	if loaded.ProviderMessageID == nil || *loaded.ProviderMessageID != "wamid.success.101" {
		t.Fatalf("expected provider_message_id wamid.success.101, got %v", loaded.ProviderMessageID)
	}
	if loaded.SentAt == nil {
		t.Fatal("expected sent_at populated")
	}

	// Next batch -> outbox closed, 0 records claimed
	count2, err := worker.ProcessBatch(context.Background())
	if err != nil || count2 != 0 {
		t.Fatalf("expected 0 processed on subsequent run, got count=%d", count2)
	}
	if sendCalls != 1 {
		t.Fatalf("expected sender to be called exactly once, got %d", sendCalls)
	}
}

func TestWorker_PermanentFailure_MovesToDeadLetter(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{
		sendFunc: func(ctx context.Context, toPhone, text string) (string, error) {
			return "", waha.ErrAuthentication
		},
	}

	worker := NewOutboxWorker(WorkerConfig{
		Store:  store,
		Sender: sender,
	})

	rec := &NotificationRecord{
		OrderID:          "ord-perm-1",
		CustomerPhone:    "+6281234567890",
		NotificationType: TypeConfirmation,
		TemplateVersion:  "v1",
		IdempotencyKey:   "order:ord-perm-1:type:CONFIRMATION:v:v1",
		MessageText:      "Halo auth fail",
	}
	_, _, err := store.CreatePending(context.Background(), rec)
	if err != nil {
		t.Fatal(err)
	}

	count, err := worker.ProcessBatch(context.Background())
	if err != nil || count != 1 {
		t.Fatalf("expected 1 processed, got count=%d, err=%v", count, err)
	}

	loaded, err := store.GetByIdempotencyKey(context.Background(), rec.IdempotencyKey)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Status != StatusDeadLetter {
		t.Fatalf("expected status DEAD_LETTER, got %s", loaded.Status)
	}
	if loaded.ErrorCategory == nil || *loaded.ErrorCategory != CategoryPermanentAuth {
		t.Fatalf("expected category PERMANENT_AUTH, got %v", loaded.ErrorCategory)
	}
	if loaded.NextRetryAt != nil {
		t.Fatalf("expected next_retry_at to be nil for dead-letter, got %v", loaded.NextRetryAt)
	}

	// Subsequent runs must ignore dead-letter
	count2, err := worker.ProcessBatch(context.Background())
	if err != nil || count2 != 0 {
		t.Fatalf("expected 0 claimed for dead-letter item, got %d", count2)
	}
}

func TestWorker_MaxAttemptsExceeded_MovesToDeadLetter(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{
		sendFunc: func(ctx context.Context, toPhone, text string) (string, error) {
			return "", waha.ErrProvider
		},
	}

	worker := NewOutboxWorker(WorkerConfig{
		Store:     store,
		Sender:    sender,
		BaseDelay: 10 * time.Millisecond,
	})

	rec := &NotificationRecord{
		OrderID:          "ord-max-1",
		CustomerPhone:    "+6281234567890",
		NotificationType: TypeConfirmation,
		TemplateVersion:  "v1",
		IdempotencyKey:   "order:ord-max-1:type:CONFIRMATION:v:v1",
		MessageText:      "Halo max attempts",
		MaxAttempts:      2,
	}
	created, _, err := store.CreatePending(context.Background(), rec)
	if err != nil {
		t.Fatal(err)
	}

	// Attempt 1: fails, schedules retry
	_, _ = worker.ProcessBatch(context.Background())
	loaded, _ := store.GetByIdempotencyKey(context.Background(), created.IdempotencyKey)
	if loaded.Status != StatusFailed || loaded.Attempts != 1 {
		t.Fatalf("expected status FAILED with attempts=1, got status=%s, attempts=%d", loaded.Status, loaded.Attempts)
	}

	// Fast-forward next_retry_at to now
	past := time.Now().UTC().Add(-1 * time.Second)
	_ = store.ScheduleRetry(context.Background(), created.ID, past, CategoryTransientProvider, "provider error")

	// Attempt 2: hits max attempts (2 >= 2) -> moves to DEAD_LETTER
	_, _ = worker.ProcessBatch(context.Background())
	loaded2, _ := store.GetByIdempotencyKey(context.Background(), created.IdempotencyKey)
	if loaded2.Status != StatusDeadLetter {
		t.Fatalf("expected DEAD_LETTER after max attempts, got %s", loaded2.Status)
	}
	if loaded2.ErrorCategory == nil || *loaded2.ErrorCategory != CategoryMaxAttemptsExceeded {
		t.Fatalf("expected category MAX_ATTEMPTS_EXCEEDED, got %v", loaded2.ErrorCategory)
	}
	if loaded2.LastError == nil || !strings.Contains(*loaded2.LastError, "max attempts reached") {
		t.Fatalf("expected last_error to mention max attempts, got %v", loaded2.LastError)
	}
}

func TestWorker_CrashRecovery_StaleProcessing(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{}
	worker := NewOutboxWorker(WorkerConfig{
		Store:          store,
		Sender:         sender,
		StaleThreshold: 100 * time.Millisecond,
	})

	rec := &NotificationRecord{
		OrderID:          "ord-stale-1",
		CustomerPhone:    "+6281234567890",
		NotificationType: TypeConfirmation,
		TemplateVersion:  "v1",
		IdempotencyKey:   "order:ord-stale-1:type:CONFIRMATION:v:v1",
		MessageText:      "Crash recovery test",
	}
	created, _, err := store.CreatePending(context.Background(), rec)
	if err != nil {
		t.Fatal(err)
	}

	// Simulate that a worker claimed it into PROCESSING and crashed
	claimed, err := store.ClaimBatchForProcessing(context.Background(), 10)
	if err != nil || len(claimed) != 1 {
		t.Fatalf("failed to claim record into PROCESSING")
	}

	// Stale threshold not met yet
	recovered, err := store.RecoverStaleProcessing(context.Background(), 1*time.Minute)
	if err != nil || recovered != 0 {
		t.Fatalf("expected 0 recovered before stale threshold, got %d", recovered)
	}

	// Simulate crash on startup recovery (threshold <= 0 resets all PROCESSING)
	recoveredOnStartup, err := store.RecoverStaleProcessing(context.Background(), 0)
	if err != nil || recoveredOnStartup != 1 {
		t.Fatalf("expected 1 recovered on startup, got %d", recoveredOnStartup)
	}

	loaded, _ := store.GetByIdempotencyKey(context.Background(), created.IdempotencyKey)
	if loaded.Status != StatusFailed {
		t.Fatalf("expected status FAILED after recovery, got %s", loaded.Status)
	}

	// Now worker can process it to success cleanly without job loss or duplication!
	count, err := worker.ProcessBatch(context.Background())
	if err != nil || count != 1 {
		t.Fatalf("expected 1 claimed and processed after recovery, got count=%d", count)
	}
	loadedAfter, _ := store.GetByIdempotencyKey(context.Background(), created.IdempotencyKey)
	if loadedAfter.Status != StatusSent {
		t.Fatalf("expected status SENT, got %s", loadedAfter.Status)
	}
}

func TestWorker_GuardReevaluation_OptOutAndPause(t *testing.T) {
	store := NewMemoryStore()
	sender := &mockSender{}
	worker := NewOutboxWorker(WorkerConfig{
		Store:  store,
		Sender: sender,
	})

	// Scenario 1: Customer opted out between retry attempts
	rec1 := &NotificationRecord{
		OrderID:          "ord-opt-retry",
		CustomerPhone:    "+6281234567890",
		NotificationType: TypeConfirmation,
		TemplateVersion:  "v1",
		IdempotencyKey:   "order:ord-opt-retry:type:CONFIRMATION:v:v1",
		MessageText:      "Test opt-out during retry",
	}
	_, _, _ = store.CreatePending(context.Background(), rec1)
	_ = store.SetOptOut(context.Background(), "+6281234567890", "STOP")

	count, _ := worker.ProcessBatch(context.Background())
	if count != 1 {
		t.Fatalf("expected 1 record claimed, got %d", count)
	}
	loaded1, _ := store.GetByIdempotencyKey(context.Background(), rec1.IdempotencyKey)
	if loaded1.Status != StatusSuppressed || loaded1.SuppressReason == nil || *loaded1.SuppressReason != string(SuppressCustomerOptedOut) {
		t.Fatalf("expected SUPPRESSED with CUSTOMER_OPTED_OUT, got status=%s, reason=%v", loaded1.Status, loaded1.SuppressReason)
	}

	// Scenario 2: Conversation paused before retry
	rec2 := &NotificationRecord{
		OrderID:          "ord-pause-retry",
		CustomerPhone:    "+6281987654321",
		NotificationType: TypeAccepted,
		TemplateVersion:  "v1",
		IdempotencyKey:   "order:ord-pause-retry:type:ACCEPTED:v:v1",
		MessageText:      "Test pause during retry",
	}
	_, _, _ = store.CreatePending(context.Background(), rec2)
	store.SetPausedPhone("+6281987654321", true)

	count2, _ := worker.ProcessBatch(context.Background())
	if count2 != 1 {
		t.Fatalf("expected 1 record claimed, got %d", count2)
	}
	loaded2, _ := store.GetByIdempotencyKey(context.Background(), rec2.IdempotencyKey)
	if loaded2.Status != StatusSuppressed || loaded2.SuppressReason == nil || *loaded2.SuppressReason != string(SuppressConversationPaused) {
		t.Fatalf("expected SUPPRESSED with CONVERSATION_PAUSED, got status=%s, reason=%v", loaded2.Status, loaded2.SuppressReason)
	}

	// Sender must NEVER have been invoked for either suppressed message
	if sender.calls != 0 {
		t.Fatalf("sender was called! expected 0 calls, got %d", sender.calls)
	}
}
