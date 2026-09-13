ALTER TABLE customers
    ADD COLUMN preferences jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(preferences) = 'object'),
    ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK (version >= 1),
    ADD COLUMN create_idempotency_key text CHECK (create_idempotency_key IS NULL OR char_length(create_idempotency_key) BETWEEN 1 AND 128);

CREATE UNIQUE INDEX customers_create_idempotency_uidx
    ON customers (create_idempotency_key)
    WHERE create_idempotency_key IS NOT NULL;
