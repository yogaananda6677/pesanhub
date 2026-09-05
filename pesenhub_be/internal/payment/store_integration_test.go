package payment

import (
	"context"
	"errors"
	"os"
	"strings"
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

type retryMidtrans struct {
	calls    int
	orderIDs []string
}

func (f *retryMidtrans) CreateQRIS(_ context.Context, orderID string, _ int64) (QRISCharge, error) {
	f.calls++
	f.orderIDs = append(f.orderIDs, orderID)
	if f.calls == 1 {
		return QRISCharge{}, &ProviderError{Kind: "timeout"}
	}
	return QRISCharge{ProviderOrderID: orderID, ProviderReference: "dummy-midtrans-tx", Status: "pending", QRCodeURL: "https://api.sandbox.midtrans.com/v2/qris/dummy-midtrans-tx/qr-code"}, nil
}

func TestCreateQRISIntegrationRetryUsesOnePaymentAndStableProviderOrderID(t *testing.T) {
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

	orderID, key := customer.NewID(), "qris-integration-"+customer.NewID()
	_, err = db.Exec(ctx, `INSERT INTO orders (id,order_number,source,status,customer_name_snapshot,subtotal_amount,total_amount,idempotency_key) VALUES ($1,$2,'CASHIER_MANUAL','PENDING','QRIS Test',27500,27500,$3)`, orderID, "ORD-QRIS-"+orderID[:8], "order-"+key)
	if err != nil {
		t.Fatal(err)
	}
	gateway := &retryMidtrans{}
	service := NewServiceWithMidtrans(NewStore(db), gateway)
	principal := customer.Principal{Subject: "staff-qris", Role: "STAFF"}

	if _, _, err = service.CreateQRIS(ctx, principal, orderID, key, "req-timeout"); !errors.Is(err, ErrMidtransUnavailable) {
		t.Fatalf("expected safe timeout, got %v", err)
	}
	p, created, err := service.CreateQRIS(ctx, principal, orderID, key, "req-retry")
	if err != nil || created || p.Status != "PENDING_PAYMENT" || p.Amount != 27500 || gateway.calls != 2 || gateway.orderIDs[0] != gateway.orderIDs[1] {
		t.Fatalf("payment=%#v created=%v calls=%d ids=%v err=%v", p, created, gateway.calls, gateway.orderIDs, err)
	}
	replay, created, err := service.CreateQRIS(ctx, principal, orderID, key, "req-replay")
	if err != nil || created || replay.ID != p.ID || gateway.calls != 2 {
		t.Fatalf("replay=%#v created=%v calls=%d err=%v", replay, created, gateway.calls, err)
	}

	var payments, attempts int
	var responseText string
	err = db.QueryRow(ctx, `SELECT (SELECT count(*) FROM payments WHERE order_id=$1 AND method='MIDTRANS_QRIS'),provider_attempt_count,provider_response_redacted::text FROM payments WHERE id=$2`, orderID, p.ID).Scan(&payments, &attempts, &responseText)
	if err != nil {
		t.Fatal(err)
	}
	if payments != 1 || attempts != 2 || strings.Contains(responseText, "server-key") || strings.Contains(responseText, "signature_key") {
		t.Fatalf("payments=%d attempts=%d response=%s", payments, attempts, responseText)
	}
}
