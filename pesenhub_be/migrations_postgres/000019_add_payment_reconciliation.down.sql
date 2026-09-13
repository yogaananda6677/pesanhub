DROP INDEX IF EXISTS payments_reconciliation_due_idx;

ALTER TABLE payments
    DROP COLUMN IF EXISTS reconciliation_alerted_at,
    DROP COLUMN IF EXISTS reconciliation_error_code,
    DROP COLUMN IF EXISTS reconciliation_last_attempt_at,
    DROP COLUMN IF EXISTS reconciliation_next_at,
    DROP COLUMN IF EXISTS reconciliation_failure_count,
    DROP COLUMN IF EXISTS reconciliation_attempt_count,
    DROP COLUMN IF EXISTS reconciliation_state;
