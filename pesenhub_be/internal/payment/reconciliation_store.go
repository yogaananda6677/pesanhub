package payment

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"database/sql"
	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
)

const reconciliationCandidateColumns = `id::text,order_id::text,provider_order_id,COALESCE(provider_reference,''),amount,reconciliation_attempt_count,reconciliation_failure_count,expires_at`

func scanReconciliationCandidate(row dbx.Row, candidate *ReconciliationCandidate) error {
	return row.Scan(&candidate.PaymentID, &candidate.OrderID, &candidate.ProviderOrderID, &candidate.ProviderReference, &candidate.Amount, &candidate.Attempt, &candidate.FailureCount, &candidate.ExpiresAt)
}

func (s *Store) ClaimDueReconciliations(ctx context.Context, limit int, now time.Time, staleAfter time.Duration) ([]ReconciliationCandidate, error) {
	if limit <= 0 {
		limit = 10
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	rows, err := tx.Query(ctx, `SELECT `+reconciliationCandidateColumns+` FROM payments
			WHERE method='MIDTRANS_QRIS' AND status IN ('UNPAID','PENDING_PAYMENT')
			  AND ((reconciliation_state IN ('DUE','RETRY') AND reconciliation_next_at <= $1)
			    OR (reconciliation_state='IN_FLIGHT' AND reconciliation_last_attempt_at <= DATE_SUB($1, INTERVAL $3 MICROSECOND)))
			ORDER BY reconciliation_next_at IS NOT NULL,reconciliation_next_at,id LIMIT $2 FOR UPDATE SKIP LOCKED`, now, limit, staleAfter.Microseconds())
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
	if err := rows.Close(); err != nil {
		return nil, err
	}
	if len(candidates) == 0 {
		_ = tx.Commit(ctx)
		return candidates, nil
	}
	ids := make([]string, len(candidates))
	for i := range candidates {
		ids[i] = candidates[i].PaymentID
		candidates[i].Attempt++
	}
	if _, err := tx.Exec(ctx, `UPDATE payments SET reconciliation_state='IN_FLIGHT',reconciliation_attempt_count=reconciliation_attempt_count+1,
		reconciliation_last_attempt_at=$1,reconciliation_error_code=NULL,updated_at=now() WHERE id = ANY($2)`, now, ids); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return candidates, nil
}

func (s *Store) ClaimReconciliation(ctx context.Context, paymentID string, now time.Time, staleAfter time.Duration) (ReconciliationCandidate, error) {
	var candidate ReconciliationCandidate
	err := scanReconciliationCandidate(s.db.QueryRow(ctx, `UPDATE payments SET reconciliation_state='IN_FLIGHT',reconciliation_attempt_count=reconciliation_attempt_count+1,reconciliation_last_attempt_at=$2,reconciliation_error_code=NULL,updated_at=now()
		WHERE id=$1 AND method='MIDTRANS_QRIS' AND status IN ('UNPAID','PENDING_PAYMENT')
		  AND (reconciliation_state IS NULL OR reconciliation_state <> 'IN_FLIGHT' OR reconciliation_last_attempt_at <= DATE_SUB($2, INTERVAL $3 MICROSECOND))
		RETURNING `+reconciliationCandidateColumns, paymentID, now, staleAfter.Microseconds()), &candidate)
	if errors.Is(err, sql.ErrNoRows) {
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
		provider_response_redacted=JSON_SET(provider_response_redacted,'$.last_reconciled_status',$4,'$.last_reconciled_at',now()),updated_at=now()
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
	tx, err := s.db.BeginTx(ctx, dbx.TxOptions{})
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
