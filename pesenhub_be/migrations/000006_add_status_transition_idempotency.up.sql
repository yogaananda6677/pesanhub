ALTER TABLE order_status_history
    ADD COLUMN idempotency_key text CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 128),
    ADD COLUMN request_hash text CHECK (request_hash IS NULL OR request_hash ~ '^[0-9a-f]{64}$');

CREATE UNIQUE INDEX order_status_history_idempotency_uidx
    ON order_status_history (order_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
