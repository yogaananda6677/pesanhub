DROP INDEX IF EXISTS order_status_history_idempotency_uidx;
ALTER TABLE order_status_history DROP COLUMN request_hash, DROP COLUMN idempotency_key;
