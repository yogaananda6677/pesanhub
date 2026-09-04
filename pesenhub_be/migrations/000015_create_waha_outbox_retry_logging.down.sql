DROP INDEX IF EXISTS idx_order_notifications_outbox;

ALTER TABLE order_notifications DROP CONSTRAINT IF EXISTS order_notifications_status_check;
ALTER TABLE order_notifications ADD CONSTRAINT order_notifications_status_check
    CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'SUPPRESSED'));

ALTER TABLE order_notifications DROP COLUMN IF EXISTS error_category;
ALTER TABLE order_notifications DROP COLUMN IF EXISTS max_attempts;
ALTER TABLE order_notifications DROP COLUMN IF EXISTS next_retry_at;
