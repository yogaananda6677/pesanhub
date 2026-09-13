DROP INDEX IF EXISTS customers_create_idempotency_uidx;
ALTER TABLE customers
    DROP COLUMN IF EXISTS create_idempotency_key,
    DROP COLUMN IF EXISTS version,
    DROP COLUMN IF EXISTS preferences;
