package payment

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"pesenhub/backend/internal/customer"
)

const reconciliationCandidateColumns = `id::text,order_id::text,provider_order_id,COALESCE(provider_reference,''),amount,reconciliation_attempt_count,reconciliation_failure_count,expires_at`

func scanReconciliationCandidate(row pgx.Row, candidate *ReconciliationCandidate) error {
	return row.Scan(&candidate.PaymentID, &candidate.OrderID, &candidate.ProviderOrderID, &candidate.ProviderReference, &candidate.Amount, &candidate.Attempt, &candidate.FailureCount, &candidate.ExpiresAt)
}

func (s *Store) ClaimDueReconciliations(ctx context.Context, limit int, now time.Time, staleAfter time.Duration) ([]ReconciliationCandidate, error) {
	if limit <= 0 {
		limit = 10
	}
	rows, err := s.db.Query(ctx, `
		WITH due AS (
			SELECT id FROM payments
			WHERE method='MIDTRANS_QRIS' AND status IN ('UNPAID','PENDING_PAYMENT')
			  AND ((reconciliation_state IN ('DUE','RETRY') AND reconciliation_next_at <= $1::timestamptz)
			    OR (reconciliation_state='IN_FLIGHT' AND reconciliation_last_attempt_at <= $1::timestamptz-make_interval(secs => $3::double precision)))
			ORDER BY reconciliation_next_at NULLS FIRST,id FOR UPDATE SKIP LOCKED LIMIT $2
		)
		UPDATE payments p SET reconciliation_state='IN_FLIGHT',reconciliation_attempt_count=p.reconciliation_attempt_count+1,
			reconciliation_last_attempt_at=$1::timestamptz,reconciliation_error_code=NULL,updated_at=now()
		FROM due WHERE p.id=due.id RETURNING p.`+reconciliationCandidateColumns, now, limit, staleAfter.Seconds())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var candidates []ReconciliationCandidate
	for rows.Next() {
		var candidate ReconciliationCandidate
		if err := rows.Scan(&candidate.PaymentID, &candidate.OrderID, &candidate.ProviderOrderID, &candidate.ProviderReference, &candidate.Amount, &candidate.Attempt, &candidate.FailureCount, &candidate.ExpiresAt); err != nil {
			return nil, err
		}
		candidates = append(candidates, candidate)
	}
	return candidates, rows.Err()
}

func (s *Store) ClaimReconciliation(ctx context.Context, paymentID string, now time.Time, staleAfter time.Duration) (ReconciliationCandidate, error) {
	var candidate ReconciliationCandidate
	err := scanReconciliationCandidate(s.db.QueryRow(ctx, `UPDATE payments SET reconciliation_state='IN_FLIGHT',reconciliation_attempt_count=reconciliation_attempt_count+1,reconciliation_last_attempt_at=$2,reconciliation_error_code=NULL,updated_at=now()
		WHERE id=$1 AND method='MIDTRANS_QRIS' AND status IN ('UNPAID','PENDING_PAYMENT')
		  AND (reconciliation_state IS DISTINCT FROM 'IN_FLIGHT' OR reconciliation_last_attempt_at <= $2::timestamptz-make_interval(secs => $3::double precision))
		RETURNING `+reconciliationCandidateColumns, paymentID, now, staleAfter.Seconds()), &candidate)
	if errors.Is(err, pgx.ErrNoRows) {
		return ReconciliationCandidate{}, ErrPaymentNotReconcilable
	}
	return candidate, err
}

func (s *Store) FinishReconciliation(ctx context.Context, candidate ReconciliationCandidate, providerStatus string, terminal bool, nextAt time.Time) error {
	state := "DUE"
	var next any = nextAt
	if terminal {
		state, next = "RESOLVED", nil
	}
	result, err := s.db.Exec(ctx, `UPDATE payments SET reconciliation_state=$2,reconciliation_next_at=$3,reconciliation_error_code=NULL,reconciliation_failure_count=0,
		provider_response_redacted=provider_response_redacted || jsonb_build_object('last_reconciled_status',$4::text,'last_reconciled_at',now()),updated_at=now()
		WHERE id=$1 AND reconciliation_attempt_count=$5`, candidate.PaymentID, state, next, providerStatus, candidate.Attempt)
	if err != nil {
		return err
	}
	if result.RowsAffected() != 1 {
		return ErrPaymentNotReconcilable
	}
	return nil
}

func (s *Store) FailReconciliation(ctx context.Context, candidate ReconciliationCandidate, code, requestID string, nextAt time.Time, maxAttempts int) (bool, error) {
	failureCount := candidate.FailureCount + 1
	alert := failureCount >= maxAttempts
	state := "RETRY"
	var next any = nextAt
	if alert {
		state, next = "ALERT", nil
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)
	result, err := tx.Exec(ctx, `UPDATE payments SET reconciliation_state=$2,reconciliation_next_at=$3,reconciliation_error_code=$4,reconciliation_failure_count=$6,
		reconciliation_alerted_at=CASE WHEN $5 THEN now() ELSE reconciliation_alerted_at END,updated_at=now()
		WHERE id=$1 AND reconciliation_state='IN_FLIGHT' AND reconciliation_attempt_count=$7`, candidate.PaymentID, state, next, code, alert, failureCount, candidate.Attempt)
	if err != nil {
		return false, err
	}
	if result.RowsAffected() != 1 {
		return false, ErrPaymentNotReconcilable
	}
	payload, _ := json.Marshal(map[string]any{"payment_id": candidate.PaymentID, "provider_order_id": candidate.ProviderOrderID, "attempt": candidate.Attempt, "error_code": code, "alert": alert})
	eventID := fmt.Sprintf("reconciliation-failure:%s:%d", candidate.PaymentID, candidate.Attempt)
	if _, err = tx.Exec(ctx, `INSERT INTO payment_events (id,payment_id,provider,provider_event_id,event_type,payload_redacted,processed_at)
		VALUES ($1,$2,'MIDTRANS',$3,$4,$5,now()) ON CONFLICT (provider,provider_event_id) DO NOTHING`, customer.NewID(), candidate.PaymentID, eventID, "MIDTRANS_RECONCILIATION_FAILED", payload); err != nil {
		return false, err
	}
	if alert {
		if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted)
			SELECT $1,'PAYMENT',$2,'MIDTRANS_RECONCILIATION_ALERT','SYSTEM','MIDTRANS_RECONCILER',$3,$4
			WHERE NOT EXISTS (SELECT 1 FROM audit_logs WHERE aggregate_type='PAYMENT' AND aggregate_id=$2 AND action='MIDTRANS_RECONCILIATION_ALERT')`, customer.NewID(), candidate.PaymentID, requestID, payload); err != nil {
			return false, err
		}
		if _, err = tx.Exec(ctx, `INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,payload,deduplication_key)
			VALUES ($1,'PAYMENT',$2,'PAYMENT_RECONCILIATION_ALERT',$3,$4) ON CONFLICT (deduplication_key) DO NOTHING`, customer.NewID(), candidate.PaymentID, payload, "payment-reconciliation-alert:"+candidate.PaymentID); err != nil {
			return false, err
		}
	}
	return alert, tx.Commit(ctx)
}
