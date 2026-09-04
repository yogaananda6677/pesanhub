DROP INDEX IF EXISTS payments_one_cash_per_order_idx;

ALTER TABLE payments
    DROP COLUMN IF EXISTS request_id,
    DROP COLUMN IF EXISTS actor_id,
    DROP COLUMN IF EXISTS request_hash;

