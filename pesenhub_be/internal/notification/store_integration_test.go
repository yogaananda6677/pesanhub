package notification

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestNotificationStoreIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping PostgreSQL integration test")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	store := NewPGStore(db)

	// Ensure test order exists in orders table
	orderID := customer.NewID()
	orderNum := "ORD-NOTIF-" + customer.NewID()[:8]
	idempotencyKey := "order-notif-test-" + customer.NewID()
	testPhone := fmt.Sprintf("+62812%08d", time.Now().UnixNano()%100000000)

	_, err = db.Exec(ctx, `
		INSERT INTO orders (id, order_number, source, customer_name_snapshot, subtotal_amount, total_amount, idempotency_key)
		VALUES ($1, $2, 'CASHIER_MANUAL', 'Integration Customer', 25000, 25000, $3)
	`, orderID, orderNum, idempotencyKey)
	if err != nil {
		t.Fatalf("failed to insert test order: %v", err)
	}

	notifKey := "order:" + orderID + ":type:CONFIRMATION:v:v1"
	rec := &NotificationRecord{
		OrderID:          orderID,
		CustomerPhone:    testPhone,
		NotificationType: TypeConfirmation,
		TemplateVersion:  "v1",
		IdempotencyKey:   notifKey,
		MessageText:      "Test confirmation message",
	}

	// 1. CreatePending
	created, isNew, err := store.CreatePending(ctx, rec)
	if err != nil {
		t.Fatalf("CreatePending failed: %v", err)
	}
	if !isNew {
		t.Fatal("expected isNew=true on initial insert")
	}
	if created.Status != StatusPending {
		t.Fatalf("expected status=PENDING, got %s", created.Status)
	}

	// 2. Duplicate CreatePending with same idempotency key
	dup, isNew2, err := store.CreatePending(ctx, rec)
	if err != nil {
		t.Fatalf("duplicate CreatePending failed: %v", err)
	}
	if isNew2 {
		t.Fatal("expected isNew=false on duplicate insert")
	}
	if dup.ID != created.ID {
		t.Fatalf("expected ID %s, got %s", created.ID, dup.ID)
	}

	// 3. MarkSent
	if err := store.MarkSent(ctx, created.ID, "wamid.integ.777"); err != nil {
		t.Fatalf("MarkSent failed: %v", err)
	}
	loaded, err := store.GetByIdempotencyKey(ctx, notifKey)
	if err != nil {
		t.Fatalf("GetByIdempotencyKey failed: %v", err)
	}
	if loaded.Status != StatusSent {
		t.Fatalf("expected StatusSent, got %s", loaded.Status)
	}
	if loaded.ProviderMessageID == nil || *loaded.ProviderMessageID != "wamid.integ.777" {
		t.Fatalf("expected provider message ID wamid.integ.777, got %v", loaded.ProviderMessageID)
	}
	if loaded.SentAt == nil {
		t.Fatal("expected sent_at to be populated")
	}

	// 4. Opt-Out flow
	optPhone := fmt.Sprintf("+62819%08d", (time.Now().UnixNano()+12345)%100000000)
	opted, err := store.IsOptedOut(ctx, optPhone)
	if err != nil {
		t.Fatalf("IsOptedOut failed: %v", err)
	}
	if opted {
		t.Fatal("expected false before opt-out")
	}

	if err := store.SetOptOut(ctx, optPhone, "Customer opted out via test"); err != nil {
		t.Fatalf("SetOptOut failed: %v", err)
	}
	opted, err = store.IsOptedOut(ctx, optPhone)
	if err != nil || !opted {
		t.Fatalf("expected true after opt-out, got %v (err: %v)", opted, err)
	}

	if err := store.RemoveOptOut(ctx, optPhone); err != nil {
		t.Fatalf("RemoveOptOut failed: %v", err)
	}
	opted, err = store.IsOptedOut(ctx, optPhone)
	if err != nil || opted {
		t.Fatalf("expected false after remove opt-out, got %v", opted)
	}

	// 5. Conversation Paused & Handoff checks
	convPhone := fmt.Sprintf("+62818%08d", (time.Now().UnixNano()+67890)%100000000)
	convID := customer.NewID()

	// Initially no conversation
	isPaused, _, err := store.IsConversationPaused(ctx, convPhone)
	if err != nil {
		t.Fatalf("IsConversationPaused error: %v", err)
	}
	if isPaused {
		t.Fatal("expected false when no conversation exists")
	}

	// Active collecting conversation
	_, err = db.Exec(ctx, `
		INSERT INTO agent_conversations (id, session, customer_phone, status, correlation_id)
		VALUES ($1, 'default', $2, 'COLLECTING', 'corr-test-1')
	`, convID, convPhone)
	if err != nil {
		t.Fatalf("failed to insert agent conversation: %v", err)
	}

	isPaused, _, err = store.IsConversationPaused(ctx, convPhone)
	if err != nil || isPaused {
		t.Fatalf("expected false for collecting conversation, got %v", isPaused)
	}

	// Mark paused
	_, err = db.Exec(ctx, `UPDATE agent_conversations SET is_paused = true WHERE id = $1`, convID)
	if err != nil {
		t.Fatal(err)
	}
	isPaused, reason, err := store.IsConversationPaused(ctx, convPhone)
	if err != nil || !isPaused || reason != SuppressConversationPaused {
		t.Fatalf("expected isPaused=true with SuppressConversationPaused, got %v, reason=%s", isPaused, reason)
	}

	// Unpause but set handoff status
	_, err = db.Exec(ctx, `UPDATE agent_conversations SET is_paused = false, status = 'HANDOFF', handoff_status = 'PENDING' WHERE id = $1`, convID)
	if err != nil {
		t.Fatal(err)
	}
	isPaused, reason, err = store.IsConversationPaused(ctx, convPhone)
	if err != nil || !isPaused || reason != SuppressHandoffActive {
		t.Fatalf("expected isPaused=true with SuppressHandoffActive, got %v, reason=%s", isPaused, reason)
	}

	// 6. ScheduleRetry & ClaimBatchForProcessing
	retryKey := "order:" + orderID + ":type:ACCEPTED:v:v1"
	retryPhone := fmt.Sprintf("+62817%08d", (time.Now().UnixNano()+33333)%100000000)
	retryRec := &NotificationRecord{
		OrderID:          orderID,
		CustomerPhone:    retryPhone,
		NotificationType: TypeAccepted,
		TemplateVersion:  "v1",
		IdempotencyKey:   retryKey,
		MessageText:      "Test accepted outbox retry",
		MaxAttempts:      3,
	}
	createdRetry, _, err := store.CreatePending(ctx, retryRec)
	if err != nil {
		t.Fatalf("failed to create pending for retry test: %v", err)
	}

	// Immediate claim
	claimed, err := store.ClaimBatchForProcessing(ctx, 10)
	if err != nil {
		t.Fatalf("ClaimBatchForProcessing failed: %v", err)
	}
	var found bool
	for _, c := range claimed {
		if c.ID == createdRetry.ID {
			found = true
			if c.Status != StatusProcessing {
				t.Fatalf("claimed record status must be PROCESSING, got %s", c.Status)
			}
		}
	}
	if !found {
		t.Fatalf("expected createdRetry to be claimed")
	}

	// Schedule retry with backoff in future
	futureRetry := time.Now().Add(5 * time.Second)
	if err := store.ScheduleRetry(ctx, createdRetry.ID, futureRetry, CategoryTransientTimeout, "gateway timeout"); err != nil {
		t.Fatalf("ScheduleRetry failed: %v", err)
	}

	loadedRetry, err := store.GetByIdempotencyKey(ctx, retryKey)
	if err != nil {
		t.Fatal(err)
	}
	if loadedRetry.Status != StatusFailed || loadedRetry.Attempts != 1 {
		t.Fatalf("expected status FAILED and attempts 1, got %s, %d", loadedRetry.Status, loadedRetry.Attempts)
	}
	if loadedRetry.ErrorCategory == nil || *loadedRetry.ErrorCategory != CategoryTransientTimeout {
		t.Fatalf("expected category TRANSIENT_TIMEOUT, got %v", loadedRetry.ErrorCategory)
	}

	// Since futureRetry > now(), ClaimBatchForProcessing should not claim it
	claimedFuture, err := store.ClaimBatchForProcessing(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range claimedFuture {
		if c.ID == createdRetry.ID {
			t.Fatalf("should not claim record whose next_retry_at is in the future")
		}
	}

	// 7. MarkDeadLetter
	if err := store.MarkDeadLetter(ctx, createdRetry.ID, CategoryPermanentAuth, "authentication_failed"); err != nil {
		t.Fatalf("MarkDeadLetter failed: %v", err)
	}
	loadedDL, err := store.GetByIdempotencyKey(ctx, retryKey)
	if err != nil {
		t.Fatal(err)
	}
	if loadedDL.Status != StatusDeadLetter {
		t.Fatalf("expected DEAD_LETTER, got %s", loadedDL.Status)
	}
	if loadedDL.ErrorCategory == nil || *loadedDL.ErrorCategory != CategoryPermanentAuth {
		t.Fatalf("expected PERMANENT_AUTH, got %v", loadedDL.ErrorCategory)
	}

	// 8. Stale Recovery
	staleKey := "order:" + orderID + ":type:COMPLETED:v:v1"
	staleRec := &NotificationRecord{
		OrderID:          orderID,
		CustomerPhone:    retryPhone,
		NotificationType: TypeCompleted,
		TemplateVersion:  "v1",
		IdempotencyKey:   staleKey,
		MessageText:      "Test stale recovery",
	}
	createdStale, _, err := store.CreatePending(ctx, staleRec)
	if err != nil {
		t.Fatal(err)
	}
	// Mark PROCESSING and set updated_at in past
	_, err = db.Exec(ctx, `UPDATE order_notifications SET status = 'PROCESSING', updated_at = now() - interval '5 minutes' WHERE id = $1`, createdStale.ID)
	if err != nil {
		t.Fatal(err)
	}

	recovered, err := store.RecoverStaleProcessing(ctx, 1*time.Minute)
	if err != nil {
		t.Fatalf("RecoverStaleProcessing failed: %v", err)
	}
	if recovered < 1 {
		t.Fatalf("expected at least 1 recovered, got %d", recovered)
	}
	loadedStale, _ := store.GetByIdempotencyKey(ctx, staleKey)
	if loadedStale.Status != StatusFailed {
		t.Fatalf("expected FAILED after stale recovery, got %s", loadedStale.Status)
	}
}
