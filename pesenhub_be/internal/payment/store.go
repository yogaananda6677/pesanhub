package payment

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"pesenhub/backend/internal/customer"
)

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

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
