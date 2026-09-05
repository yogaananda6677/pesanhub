package payment

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"pesenhub/backend/internal/customer"
)

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

const paymentColumns = `id::text,order_id::text,method,status,amount,version,paid_at,created_at,updated_at,COALESCE(provider_order_id,''),COALESCE(provider_reference,''),COALESCE(qr_code_url,''),expires_at`

func scanPayment(row pgx.Row, p *Payment) error {
	return row.Scan(&p.ID, &p.OrderID, &p.Method, &p.Status, &p.Amount, &p.Version, &p.PaidAt, &p.CreatedAt, &p.UpdatedAt, &p.ProviderOrderID, &p.ProviderReference, &p.QRCodeURL, &p.ExpiresAt)
}

func (s *Store) ApplyMidtransWebhook(ctx context.Context, notification MidtransNotification, eventID, requestID string, occurredAt *time.Time) (WebhookResult, error) {
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return WebhookResult{}, err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "MIDTRANS_WEBHOOK:"+notification.OrderID); err != nil {
		return WebhookResult{}, err
	}
	var p Payment
	if err = scanPayment(tx.QueryRow(ctx, `SELECT `+paymentColumns+` FROM payments WHERE provider_order_id=$1 AND method='MIDTRANS_QRIS' FOR UPDATE`, notification.OrderID), &p); errors.Is(err, pgx.ErrNoRows) {
		return WebhookResult{}, ErrPaymentNotFound
	} else if err != nil {
		return WebhookResult{}, err
	}
	amount, err := parseIDRAmount(notification.GrossAmount)
	if err != nil || amount != p.Amount {
		return WebhookResult{}, ErrWebhookAmount
	}
	if p.ProviderReference != "" && p.ProviderReference != notification.TransactionID {
		return WebhookResult{}, ErrWebhookReference
	}
	var duplicate bool
	err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM payment_events WHERE provider='MIDTRANS' AND provider_event_id=$1)`, eventID).Scan(&duplicate)
	if err != nil {
		return WebhookResult{}, err
	}
	if duplicate {
		if err = tx.Commit(ctx); err != nil {
			return WebhookResult{}, err
		}
		return WebhookResult{Payment: p, Duplicate: true}, nil
	}
	target, err := mapMidtransStatus(notification)
	if err != nil {
		return WebhookResult{}, err
	}
	applied := paymentStatusRank(target) > paymentStatusRank(p.Status)
	fromStatus := p.Status
	redacted, _ := json.Marshal(map[string]any{
		"transaction_id": notification.TransactionID, "order_id": notification.OrderID, "gross_amount": notification.GrossAmount,
		"provider_status": notification.TransactionStatus, "fraud_status": notification.FraudStatus, "from_status": fromStatus, "target_status": target, "applied": applied,
	})
	if applied {
		paidAt := p.PaidAt
		if target == "PAID" {
			paidAt = occurredAt
			if paidAt == nil {
				now := time.Now().UTC()
				paidAt = &now
			}
		}
		err = scanPayment(tx.QueryRow(ctx, `UPDATE payments SET status=$2,provider_reference=COALESCE(NULLIF(provider_reference,''),$3),provider_attempt_state='SUCCEEDED',provider_error_code=NULL,provider_response_redacted=$4,paid_at=CASE WHEN $2='PAID' THEN $5 ELSE paid_at END,version=version+1,updated_at=now() WHERE id=$1 RETURNING `+paymentColumns, p.ID, target, notification.TransactionID, redacted, paidAt), &p)
		if err != nil {
			return WebhookResult{}, err
		}
	} else if p.ProviderReference == "" {
		if _, err = tx.Exec(ctx, `UPDATE payments SET provider_reference=$2,provider_attempt_state='SUCCEEDED',provider_error_code=NULL,provider_response_redacted=$3,updated_at=now() WHERE id=$1`, p.ID, notification.TransactionID, redacted); err != nil {
			return WebhookResult{}, err
		}
		p.ProviderReference = notification.TransactionID
	}
	eventType := "MIDTRANS_PAYMENT_STATUS_IGNORED"
	if applied {
		eventType = "MIDTRANS_PAYMENT_STATUS_CHANGED"
	}
	terminal := target != "PENDING_PAYMENT"
	if terminal || paymentStatusRank(p.Status) >= paymentStatusRank("FAILED") {
		if _, err = tx.Exec(ctx, `UPDATE payments SET reconciliation_state='RESOLVED',reconciliation_next_at=NULL,reconciliation_error_code=NULL,reconciliation_failure_count=0 WHERE id=$1`, p.ID); err != nil {
			return WebhookResult{}, err
		}
	} else {
		next := time.Now().UTC().Add(2 * time.Minute)
		if p.ExpiresAt != nil && p.ExpiresAt.Before(next) {
			next = *p.ExpiresAt
		}
		if _, err = tx.Exec(ctx, `UPDATE payments SET reconciliation_state='DUE',reconciliation_next_at=$2,reconciliation_error_code=NULL,reconciliation_failure_count=0 WHERE id=$1`, p.ID, next); err != nil {
			return WebhookResult{}, err
		}
	}
	if _, err = tx.Exec(ctx, `INSERT INTO payment_events (id,payment_id,provider,provider_event_id,event_type,payload_redacted,processed_at) VALUES ($1,$2,'MIDTRANS',$3,$4,$5,now())`, customer.NewID(), p.ID, eventID, eventType, redacted); err != nil {
		return WebhookResult{}, err
	}
	if applied {
		if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'PAYMENT',$2,'MIDTRANS_PAYMENT_STATUS_CHANGED','SYSTEM','MIDTRANS',$3,$4)`, customer.NewID(), p.ID, requestID, redacted); err != nil {
			return WebhookResult{}, err
		}
		outbox, _ := json.Marshal(map[string]any{"payment_id": p.ID, "order_id": p.OrderID, "status": p.Status, "version": p.Version})
		if _, err = tx.Exec(ctx, `INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,payload,deduplication_key) VALUES ($1,'PAYMENT',$2,'PAYMENT_STATUS_CHANGED',$3,$4)`, customer.NewID(), p.ID, outbox, fmt.Sprintf("payment-status:%s:%d", p.ID, p.Version)); err != nil {
			return WebhookResult{}, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return WebhookResult{}, err
	}
	return WebhookResult{Payment: p, Applied: applied}, nil
}

func paymentStatusRank(status string) int {
	switch status {
	case "UNPAID":
		return 0
	case "PENDING_PAYMENT":
		return 1
	case "FAILED", "EXPIRED":
		return 2
	case "PAID":
		return 3
	case "REFUNDED":
		return 4
	default:
		return -1
	}
}

func (s *Store) PrepareQRIS(ctx context.Context, orderID, key, hash, actorID, requestID string) (Payment, bool, bool, error) {
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Payment{}, false, false, err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "MIDTRANS_QRIS:"+orderID); err != nil {
		return Payment{}, false, false, err
	}

	var p Payment
	var storedHash, storedActor, attemptState string
	err = tx.QueryRow(ctx, `SELECT `+paymentColumns+`,COALESCE(request_hash,''),COALESCE(actor_id,''),COALESCE(provider_attempt_state,'') FROM payments WHERE idempotency_key=$1`, key).Scan(
		&p.ID, &p.OrderID, &p.Method, &p.Status, &p.Amount, &p.Version, &p.PaidAt, &p.CreatedAt, &p.UpdatedAt, &p.ProviderOrderID, &p.ProviderReference, &p.QRCodeURL, &p.ExpiresAt, &storedHash, &storedActor, &attemptState,
	)
	if err == nil {
		if storedHash != hash || storedActor != actorID || p.Method != "MIDTRANS_QRIS" {
			return Payment{}, false, false, ErrIdempotencyConflict
		}
		if attemptState == "PERMANENT_FAILURE" {
			return Payment{}, false, false, ErrMidtransRejected
		}
		if attemptState == "SUCCEEDED" || attemptState == "IN_FLIGHT" {
			return p, false, false, tx.Commit(ctx)
		}
		_, err = tx.Exec(ctx, `UPDATE payments SET provider_attempt_state='IN_FLIGHT',provider_attempt_count=provider_attempt_count+1,provider_last_attempt_at=now(),provider_error_code=NULL,updated_at=now() WHERE id=$1`, p.ID)
		if err != nil {
			return Payment{}, false, false, err
		}
		if err = tx.Commit(ctx); err != nil {
			return Payment{}, false, false, err
		}
		return p, true, false, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, false, false, err
	}

	var total int64
	var orderStatus string
	err = tx.QueryRow(ctx, `SELECT total_amount,status FROM orders WHERE id=$1 FOR UPDATE`, orderID).Scan(&total, &orderStatus)
	if errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, false, false, ErrOrderNotFound
	}
	if err != nil {
		return Payment{}, false, false, err
	}
	if orderStatus == "REJECTED" || orderStatus == "CANCELLED" {
		return Payment{}, false, false, ErrOrderNotPayable
	}
	if total <= 0 {
		return Payment{}, false, false, &ValidationError{Field: "order.total_amount", Reason: "must_be_positive"}
	}
	if err = scanPayment(tx.QueryRow(ctx, `SELECT `+paymentColumns+` FROM payments WHERE order_id=$1 AND method='MIDTRANS_QRIS'`, orderID), &p); err == nil {
		return Payment{}, false, false, ErrIdempotencyConflict
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, false, false, err
	}

	p = Payment{ID: customer.NewID(), OrderID: orderID, Method: "MIDTRANS_QRIS", Status: "UNPAID", Amount: total, Version: 1}
	p.ProviderOrderID = "PH-" + p.ID
	err = tx.QueryRow(ctx, `INSERT INTO payments (id,order_id,method,status,amount,idempotency_key,version,request_hash,actor_id,request_id,provider_order_id,provider_attempt_state,provider_attempt_count,provider_last_attempt_at) VALUES ($1,$2,'MIDTRANS_QRIS','UNPAID',$3,$4,1,$5,$6,$7,$8,'IN_FLIGHT',1,now()) RETURNING created_at,updated_at`, p.ID, orderID, total, key, hash, actorID, requestID, p.ProviderOrderID).Scan(&p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return Payment{}, false, false, err
	}
	redacted, _ := json.Marshal(map[string]any{"payment_id": p.ID, "order_id": orderID, "provider_order_id": p.ProviderOrderID, "method": "MIDTRANS_QRIS", "status": "UNPAID", "amount": total})
	if _, err = tx.Exec(ctx, `INSERT INTO payment_events (id,payment_id,provider,provider_event_id,event_type,payload_redacted,processed_at) VALUES ($1,$2,'MIDTRANS',$3,'QRIS_CHARGE_REQUESTED',$4,now())`, customer.NewID(), p.ID, "charge-request:"+p.ID, redacted); err != nil {
		return Payment{}, false, false, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'PAYMENT',$2,'QRIS_CHARGE_REQUESTED','STAFF',$3,$4,$5)`, customer.NewID(), p.ID, actorID, requestID, redacted); err != nil {
		return Payment{}, false, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Payment{}, false, false, err
	}
	return p, true, true, nil
}

func (s *Store) CompleteQRIS(ctx context.Context, original Payment, charge QRISCharge, actorID, requestID string) (Payment, error) {
	if charge.ProviderOrderID != original.ProviderOrderID {
		return Payment{}, ErrMidtransUnavailable
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Payment{}, err
	}
	defer tx.Rollback(ctx)
	redacted, _ := json.Marshal(map[string]any{"transaction_id": charge.ProviderReference, "order_id": charge.ProviderOrderID, "transaction_status": charge.Status, "qr_code_url": charge.QRCodeURL})
	var p Payment
	nextReconciliation := time.Now().UTC().Add(2 * time.Minute)
	if charge.ExpiresAt != nil && charge.ExpiresAt.Before(nextReconciliation) {
		nextReconciliation = *charge.ExpiresAt
	}
	err = scanPayment(tx.QueryRow(ctx, `UPDATE payments SET status='PENDING_PAYMENT',provider_reference=$2,qr_code_url=$3,expires_at=$4,provider_attempt_state='SUCCEEDED',provider_error_code=NULL,provider_response_redacted=$5,reconciliation_state='DUE',reconciliation_next_at=$6,version=version+1,updated_at=now() WHERE id=$1 AND provider_attempt_state='IN_FLIGHT' RETURNING `+paymentColumns, original.ID, charge.ProviderReference, charge.QRCodeURL, charge.ExpiresAt, redacted, nextReconciliation), &p)
	if errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, ErrIdempotencyConflict
	}
	if err != nil {
		return Payment{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO payment_events (id,payment_id,provider,provider_event_id,event_type,payload_redacted,processed_at) VALUES ($1,$2,'MIDTRANS',$3,'QRIS_CHARGE_CREATED',$4,now()) ON CONFLICT (provider,provider_event_id) DO NOTHING`, customer.NewID(), p.ID, "charge:"+charge.ProviderReference, redacted); err != nil {
		return Payment{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'PAYMENT',$2,'QRIS_CHARGE_CREATED','STAFF',$3,$4,$5)`, customer.NewID(), p.ID, actorID, requestID, redacted); err != nil {
		return Payment{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,payload,deduplication_key) VALUES ($1,'PAYMENT',$2,'QRIS_CHARGE_CREATED',$3,$4) ON CONFLICT (deduplication_key) DO NOTHING`, customer.NewID(), p.ID, redacted, "qris-charge:"+p.ID); err != nil {
		return Payment{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Payment{}, err
	}
	return p, nil
}

func (s *Store) FailQRIS(ctx context.Context, p Payment, code string, permanent bool, actorID, requestID string) error {
	state, status := "UNKNOWN", "UNPAID"
	if permanent {
		state, status = "PERMANENT_FAILURE", "FAILED"
	}
	redacted, _ := json.Marshal(map[string]any{"payment_id": p.ID, "provider_order_id": p.ProviderOrderID, "status": status, "error_code": code})
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	reconciliationState := "DUE"
	var reconciliationNext any = time.Now().UTC()
	if permanent {
		reconciliationState, reconciliationNext = "RESOLVED", nil
	}
	if _, err = tx.Exec(ctx, `UPDATE payments SET status=$2,provider_attempt_state=$3,provider_error_code=$4,provider_response_redacted=$5,reconciliation_state=$6,reconciliation_next_at=$7,version=version+1,updated_at=now() WHERE id=$1 AND provider_attempt_state='IN_FLIGHT'`, p.ID, status, state, code, redacted, reconciliationState, reconciliationNext); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO payment_events (id,payment_id,provider,provider_event_id,event_type,payload_redacted,processed_at) VALUES ($1,$2,'MIDTRANS',$3,$4,$5,now()) ON CONFLICT (provider,provider_event_id) DO NOTHING`, customer.NewID(), p.ID, "charge-failure:"+p.ID+":"+code, "QRIS_CHARGE_"+state, redacted); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'PAYMENT',$2,$3,'STAFF',$4,$5,$6)`, customer.NewID(), p.ID, "QRIS_CHARGE_"+state, actorID, requestID, redacted); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Store) RecordCash(ctx context.Context, orderID string, in CashInput, key, hash, actorID, requestID string) (Payment, bool, error) {
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Payment{}, false, err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "CASH_PAYMENT:"+orderID); err != nil {
		return Payment{}, false, err
	}

	var existing Payment
	var storedHash, storedActor string
	err = tx.QueryRow(ctx, `SELECT id::text,order_id::text,method,status,amount,version,paid_at,created_at,updated_at,request_hash,actor_id FROM payments WHERE idempotency_key=$1`, key).Scan(&existing.ID, &existing.OrderID, &existing.Method, &existing.Status, &existing.Amount, &existing.Version, &existing.PaidAt, &existing.CreatedAt, &existing.UpdatedAt, &storedHash, &storedActor)
	if err == nil {
		if storedHash != hash || storedActor != actorID {
			return Payment{}, false, ErrIdempotencyConflict
		}
		return existing, false, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, false, err
	}

	var total int64
	var status string
	err = tx.QueryRow(ctx, `SELECT total_amount,status FROM orders WHERE id=$1 FOR UPDATE`, orderID).Scan(&total, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, false, ErrOrderNotFound
	}
	if err != nil {
		return Payment{}, false, err
	}
	if status == "REJECTED" || status == "CANCELLED" {
		return Payment{}, false, ErrOrderNotPayable
	}
	if in.Amount != total {
		return Payment{}, false, ErrAmountMismatch
	}

	// One cash payment per order. A different key must not create a second payment.
	err = tx.QueryRow(ctx, `SELECT id::text,order_id::text,method,status,amount,version,paid_at,created_at,updated_at FROM payments WHERE order_id=$1 AND method='CASH'`, orderID).Scan(&existing.ID, &existing.OrderID, &existing.Method, &existing.Status, &existing.Amount, &existing.Version, &existing.PaidAt, &existing.CreatedAt, &existing.UpdatedAt)
	if err == nil {
		return Payment{}, false, ErrIdempotencyConflict
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, false, err
	}

	p := Payment{ID: customer.NewID(), OrderID: orderID, Method: "CASH", Status: "PAID", Amount: in.Amount, Version: 1}
	err = tx.QueryRow(ctx, `INSERT INTO payments (id,order_id,method,status,amount,idempotency_key,version,paid_at,request_hash,actor_id,request_id) VALUES ($1,$2,'CASH','PAID',$3,$4,1,now(),$5,$6,$7) RETURNING paid_at,created_at,updated_at`, p.ID, orderID, in.Amount, key, hash, actorID, requestID).Scan(&p.PaidAt, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return Payment{}, false, err
	}
	redacted, _ := json.Marshal(map[string]any{"payment_id": p.ID, "order_id": orderID, "method": "CASH", "status": "PAID", "amount": in.Amount})
	if _, err = tx.Exec(ctx, `INSERT INTO payment_events (id,payment_id,provider,provider_event_id,event_type,payload_redacted,processed_at) VALUES ($1,$2,'CASH',$3,'CASH_PAYMENT_RECORDED',$4,now())`, customer.NewID(), p.ID, "cash:"+key, redacted); err != nil {
		return Payment{}, false, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'PAYMENT',$2,'CASH_PAYMENT_RECORDED','STAFF',$3,$4,$5)`, customer.NewID(), p.ID, actorID, requestID, redacted); err != nil {
		return Payment{}, false, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,payload,deduplication_key) VALUES ($1,'PAYMENT',$2,'CASH_PAYMENT_RECORDED',$3,$4)`, customer.NewID(), p.ID, redacted, "cash-payment:"+p.ID); err != nil {
		return Payment{}, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Payment{}, false, err
	}
	return p, true, nil
}
