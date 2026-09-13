ALTER TABLE payments
    ADD COLUMN reconciliation_state text CHECK (reconciliation_state IS NULL OR reconciliation_state IN ('DUE', 'IN_FLIGHT', 'RETRY', 'RESOLVED', 'ALERT')),
    ADD COLUMN reconciliation_attempt_count integer NOT NULL DEFAULT 0 CHECK (reconciliation_attempt_count >= 0),
    ADD COLUMN reconciliation_failure_count integer NOT NULL DEFAULT 0 CHECK (reconciliation_failure_count >= 0),
    ADD COLUMN reconciliation_next_at timestamptz,
    ADD COLUMN reconciliation_last_attempt_at timestamptz,
    ADD COLUMN reconciliation_error_code text,
    ADD COLUMN reconciliation_alerted_at timestamptz;

CREATE INDEX payments_reconciliation_due_idx
    ON payments (reconciliation_next_at, id)
    WHERE method = 'MIDTRANS_QRIS'
      AND reconciliation_state IN ('DUE', 'RETRY', 'IN_FLIGHT');

UPDATE payments
SET reconciliation_state = 'DUE',
    reconciliation_next_at = CASE
        WHEN provider_attempt_state = 'UNKNOWN' THEN now()
        WHEN expires_at IS NOT NULL THEN expires_at
        ELSE now()
    END
WHERE method = 'MIDTRANS_QRIS'
  AND status IN ('UNPAID', 'PENDING_PAYMENT');
