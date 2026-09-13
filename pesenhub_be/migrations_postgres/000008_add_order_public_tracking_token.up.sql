ALTER TABLE orders ADD COLUMN IF NOT EXISTS public_tracking_token text UNIQUE;
CREATE INDEX IF NOT EXISTS orders_public_tracking_token_idx ON orders (public_tracking_token) WHERE public_tracking_token IS NOT NULL;
