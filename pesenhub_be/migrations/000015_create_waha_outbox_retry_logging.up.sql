ALTER TABLE order_notifications
    ADD COLUMN next_retry_at timestamptz,
    ADD COLUMN max_attempts integer NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
    ADD COLUMN error_category text CHECK (error_category IS NULL OR error_category IN (
        'TRANSIENT_TIMEOUT',
        'TRANSIENT_NETWORK',
        'TRANSIENT_PROVIDER',
        'SESSION_NOT_READY',
        'PERMANENT_VALIDATION',
        'PERMANENT_AUTH',
        'MAX_ATTEMPTS_EXCEEDED',
        'UNKNOWN'
    ));

ALTER TABLE order_notifications DROP CONSTRAINT IF EXISTS order_notifications_status_check;
ALTER TABLE order_notifications ADD CONSTRAINT order_notifications_status_check
    CHECK (status IN ('PENDING', 'PROCESSING', 'SENT', 'FAILED', 'SUPPRESSED', 'DEAD_LETTER'));

CREATE INDEX idx_order_notifications_outbox
    ON order_notifications (status, next_retry_at, created_at)
    WHERE status IN ('PENDING', 'PROCESSING', 'FAILED');
