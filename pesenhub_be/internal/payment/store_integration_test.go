package payment

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

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

func TestMidtransReconciliationIntegrationExpiryAndBoundedAlert(t *testing.T) {
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
	now := time.Now().UTC().Truncate(time.Second)

	insertPayment := func(label string, attempts int) (string, string, string) {
		t.Helper()
		orderID, paymentID := customer.NewID(), customer.NewID()
		providerOrderID := "PH-" + paymentID
		_, insertErr := db.Exec(ctx, `INSERT INTO orders (id,order_number,source,status,customer_name_snapshot,subtotal_amount,total_amount,idempotency_key)
			VALUES ($1,$2,'CASHIER_MANUAL','PENDING','Reconciliation Test',27500,27500,$3)`, orderID, "ORD-RECON-"+paymentID[:8], "order-recon-"+paymentID)
		if insertErr != nil {
			t.Fatal(insertErr)
		}
		_, insertErr = db.Exec(ctx, `INSERT INTO payments (id,order_id,method,status,amount,idempotency_key,provider_order_id,provider_reference,provider_attempt_state,request_hash,actor_id,request_id,expires_at,reconciliation_state,reconciliation_next_at,reconciliation_attempt_count,reconciliation_failure_count)
			VALUES ($1,$2,'MIDTRANS_QRIS','PENDING_PAYMENT',27500,$3,$4,$5,'SUCCEEDED','hash','staff-recon','req-create',$6,'DUE',$7,$8,$8)`, paymentID, orderID, "payment-recon-"+paymentID, providerOrderID, "tx-"+label, now.Add(-time.Minute), now.Add(-time.Second), attempts)
		if insertErr != nil {
			t.Fatal(insertErr)
		}
		return orderID, paymentID, providerOrderID
	}

	orderID, paymentID, providerOrderID := insertPayment("expiry", 0)
	pending := MidtransNotification{OrderID: providerOrderID, TransactionID: "tx-expiry", TransactionStatus: "pending", StatusCode: "201", GrossAmount: "27500.00", PaymentType: "qris", Currency: "IDR"}
	store := NewStore(db)
	gateway := &reconciliationGatewayStub{notification: pending}
	reconciler := NewReconciler(ReconcilerConfig{Store: store, Gateway: gateway, MaxAttempts: 3, BaseDelay: time.Second, Now: func() time.Time { return now }})
	result, err := reconciler.ReconcilePayment(ctx, paymentID, "req-pending-expired")
	if err != nil || result.Outcome != "retry" {
		t.Fatalf("pending result=%+v err=%v", result, err)
	}
	_, err = db.Exec(ctx, `UPDATE payments SET reconciliation_next_at=$2 WHERE id=$1`, paymentID, now.Add(-time.Second))
	if err != nil {
		t.Fatal(err)
	}
	gateway.notification.TransactionStatus, gateway.notification.StatusCode = "expire", "407"
	result, err = reconciler.ReconcilePayment(ctx, paymentID, "req-provider-expire")
	if err != nil || result.Outcome != "success" || !result.Applied || result.Payment.Status != "EXPIRED" {
		t.Fatalf("expiry result=%+v err=%v", result, err)
	}
	if _, err = reconciler.ReconcilePayment(ctx, paymentID, "req-terminal"); !errors.Is(err, ErrPaymentNotReconcilable) {
		t.Fatalf("expected terminal rejection, got %v", err)
	}
	var paymentStatus, reconciliationState, orderStatus string
	var payments, failureEvents, statusEvents int
	err = db.QueryRow(ctx, `SELECT p.status,p.reconciliation_state,o.status,
		(SELECT count(*) FROM payments WHERE order_id=$2),
		(SELECT count(*) FROM payment_events WHERE payment_id=$1 AND event_type='MIDTRANS_RECONCILIATION_FAILED'),
		(SELECT count(*) FROM payment_events WHERE payment_id=$1 AND event_type='MIDTRANS_PAYMENT_STATUS_CHANGED')
		FROM payments p JOIN orders o ON o.id=p.order_id WHERE p.id=$1`, paymentID, orderID).Scan(&paymentStatus, &reconciliationState, &orderStatus, &payments, &failureEvents, &statusEvents)
	if err != nil {
		t.Fatal(err)
	}
	if paymentStatus != "EXPIRED" || reconciliationState != "RESOLVED" || orderStatus != "PENDING" || payments != 1 || failureEvents != 1 || statusEvents != 1 {
		t.Fatalf("payment=%s reconciliation=%s order=%s counts=%d/%d/%d", paymentStatus, reconciliationState, orderStatus, payments, failureEvents, statusEvents)
	}

	_, alertPaymentID, _ := insertPayment("alert", 2)
	alertGateway := &reconciliationGatewayStub{err: &ProviderError{Kind: "timeout"}}
	alertReconciler := NewReconciler(ReconcilerConfig{Store: store, Gateway: alertGateway, MaxAttempts: 3, BaseDelay: time.Second, Now: func() time.Time { return now }})
	alertResult, err := alertReconciler.ReconcilePayment(ctx, alertPaymentID, "req-alert")
	if err != nil || alertResult.Outcome != "alert" {
		t.Fatalf("alert result=%+v err=%v", alertResult, err)
	}
	var state, code string
	var attempts, alerts, outbox int
	err = db.QueryRow(ctx, `SELECT reconciliation_state,reconciliation_attempt_count,reconciliation_error_code,
		(SELECT count(*) FROM audit_logs WHERE aggregate_id=$1 AND action='MIDTRANS_RECONCILIATION_ALERT'),
		(SELECT count(*) FROM outbox_events WHERE aggregate_id=$1 AND event_type='PAYMENT_RECONCILIATION_ALERT')
		FROM payments WHERE id=$1`, alertPaymentID).Scan(&state, &attempts, &code, &alerts, &outbox)
	if err != nil {
		t.Fatal(err)
	}
	if state != "ALERT" || attempts != 3 || code != "timeout" || alerts != 1 || outbox != 1 {
		t.Fatalf("state=%s attempts=%d code=%s alerts=%d outbox=%d", state, attempts, code, alerts, outbox)
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

func TestApplyMidtransWebhookIntegrationIsIdempotentAndMonotonic(t *testing.T) {
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

	orderID, paymentID := customer.NewID(), customer.NewID()
	providerOrderID, transactionID := "PH-"+paymentID, "tx-webhook-"+paymentID
	_, err = db.Exec(ctx, `INSERT INTO orders (id,order_number,source,status,customer_name_snapshot,subtotal_amount,total_amount,idempotency_key) VALUES ($1,$2,'CASHIER_MANUAL','PENDING','Webhook Test',27500,27500,$3)`, orderID, "ORD-WEBHOOK-"+orderID[:8], "order-webhook-"+orderID)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(ctx, `INSERT INTO payments (id,order_id,method,status,amount,idempotency_key,provider_order_id,provider_attempt_state,request_hash,actor_id,request_id) VALUES ($1,$2,'MIDTRANS_QRIS','UNPAID',27500,$3,$4,'SUCCEEDED','hash','staff-webhook','req-create')`, paymentID, orderID, "payment-webhook-"+paymentID, providerOrderID)
	if err != nil {
		t.Fatal(err)
	}
	store := NewStore(db)
	base := MidtransNotification{OrderID: providerOrderID, TransactionID: transactionID, GrossAmount: "27500.00", PaymentType: "qris", Currency: "IDR"}

	apply := func(status, statusCode, fraud, requestID string) WebhookResult {
		t.Helper()
		n := base
		n.TransactionStatus, n.StatusCode, n.FraudStatus = status, statusCode, fraud
		result, applyErr := store.ApplyMidtransWebhook(ctx, n, midtransEventID(n), requestID, nil)
		if applyErr != nil {
			t.Fatalf("apply %s: %v", status, applyErr)
		}
		return result
	}
	if result := apply("pending", "201", "", "req-pending"); !result.Applied || result.Payment.Status != "PENDING_PAYMENT" {
		t.Fatalf("pending=%+v", result)
	}
	paid := apply("settlement", "200", "accept", "req-paid")
	if !paid.Applied || paid.Payment.Status != "PAID" || paid.Payment.PaidAt == nil {
		t.Fatalf("paid=%+v", paid)
	}
	late := apply("pending", "201", "accept", "req-late")
	if late.Applied || late.Payment.Status != "PAID" {
		t.Fatalf("late=%+v", late)
	}
	refunded := apply("refund", "200", "accept", "req-refund")
	if !refunded.Applied || refunded.Payment.Status != "REFUNDED" {
		t.Fatalf("refunded=%+v", refunded)
	}
	duplicate := apply("settlement", "200", "accept", "req-duplicate")
	if !duplicate.Duplicate || duplicate.Applied || duplicate.Payment.Status != "REFUNDED" {
		t.Fatalf("duplicate=%+v", duplicate)
	}

	badAmount := base
	badAmount.TransactionStatus, badAmount.StatusCode, badAmount.GrossAmount = "settlement", "200", "1.00"
	if _, err = store.ApplyMidtransWebhook(ctx, badAmount, midtransEventID(badAmount), "req-bad-amount", nil); !errors.Is(err, ErrWebhookAmount) {
		t.Fatalf("amount error=%v", err)
	}
	badReference := base
	badReference.TransactionID, badReference.TransactionStatus, badReference.StatusCode = "tx-other", "settlement", "200"
	if _, err = store.ApplyMidtransWebhook(ctx, badReference, midtransEventID(badReference), "req-bad-reference", nil); !errors.Is(err, ErrWebhookReference) {
		t.Fatalf("reference error=%v", err)
	}

	var paymentStatus, orderStatus string
	var version, events, audits, outbox int
	var eventPayloads string
	err = db.QueryRow(ctx, `SELECT p.status,p.version,o.status,(SELECT count(*) FROM payment_events WHERE payment_id=p.id AND event_type LIKE 'MIDTRANS_PAYMENT_STATUS_%'),(SELECT count(*) FROM audit_logs WHERE aggregate_id=p.id AND action='MIDTRANS_PAYMENT_STATUS_CHANGED'),(SELECT count(*) FROM outbox_events WHERE aggregate_id=p.id AND event_type='PAYMENT_STATUS_CHANGED'),(SELECT string_agg(payload_redacted::text,'') FROM payment_events WHERE payment_id=p.id) FROM payments p JOIN orders o ON o.id=p.order_id WHERE p.id=$1`, paymentID).Scan(&paymentStatus, &version, &orderStatus, &events, &audits, &outbox, &eventPayloads)
	if err != nil {
		t.Fatal(err)
	}
	if paymentStatus != "REFUNDED" || version != 4 || orderStatus != "PENDING" || events != 4 || audits != 3 || outbox != 3 {
		t.Fatalf("payment=%s v%d order=%s counts=%d/%d/%d", paymentStatus, version, orderStatus, events, audits, outbox)
	}
	if strings.Contains(eventPayloads, "signature_key") || strings.Contains(eventPayloads, webhookTestKey) {
		t.Fatalf("sensitive event payload: %s", eventPayloads)
	}
}
