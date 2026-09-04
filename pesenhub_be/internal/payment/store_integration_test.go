package payment

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"pesenhub/backend/internal/customer"
)

func TestRecordCashIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	orderID, key := customer.NewID(), "cash-integration-"+customer.NewID()
	_, err = db.Exec(ctx, `INSERT INTO orders (id,order_number,source,status,customer_name_snapshot,subtotal_amount,total_amount,idempotency_key) VALUES ($1,$2,'CASHIER_MANUAL','PENDING','Cash Test',25000,25000,$3)`, orderID, "ORD-CASH-"+orderID[:8], "order-"+key)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(NewStore(db))
	principal := customer.Principal{Subject: "staff-cash", Role: "STAFF"}

	if _, _, err = s.RecordCash(ctx, principal, orderID, CashInput{Amount: 24000}, key+"-mismatch", "req-mismatch"); !errors.Is(err, ErrAmountMismatch) {
		t.Fatalf("expected mismatch, got %v", err)
	}
	p, created, err := s.RecordCash(ctx, principal, orderID, CashInput{Amount: 25000}, key, "req-create")
	if err != nil || !created || p.Status != "PAID" {
		t.Fatalf("create=%#v created=%v err=%v", p, created, err)
	}
	replay, created, err := s.RecordCash(ctx, principal, orderID, CashInput{Amount: 25000}, key, "req-retry")
	if err != nil || created || replay.ID != p.ID {
		t.Fatalf("replay=%#v created=%v err=%v", replay, created, err)
	}
	if _, _, err = s.RecordCash(ctx, customer.Principal{Subject: "other", Role: "STAFF"}, orderID, CashInput{Amount: 25000}, key, "req-other"); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("expected actor conflict, got %v", err)
	}

	var orderStatus string
	var payments, events, audits, outbox int
	err = db.QueryRow(ctx, `SELECT status,(SELECT count(*) FROM payments WHERE order_id=$1),(SELECT count(*) FROM payment_events WHERE payment_id=$2),(SELECT count(*) FROM audit_logs WHERE aggregate_type='PAYMENT' AND aggregate_id=$2),(SELECT count(*) FROM outbox_events WHERE aggregate_type='PAYMENT' AND aggregate_id=$2) FROM orders WHERE id=$1`, orderID, p.ID).Scan(&orderStatus, &payments, &events, &audits, &outbox)
	if err != nil {
		t.Fatal(err)
	}
	if orderStatus != "PENDING" || payments != 1 || events != 1 || audits != 1 || outbox != 1 {
		t.Fatalf("status=%s counts=%d/%d/%d/%d", orderStatus, payments, events, audits, outbox)
	}
}
