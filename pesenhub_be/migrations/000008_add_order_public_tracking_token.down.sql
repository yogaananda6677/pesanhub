DROP INDEX IF EXISTS orders_public_tracking_token_idx;
ALTER TABLE orders DROP COLUMN IF EXISTS public_tracking_token;
