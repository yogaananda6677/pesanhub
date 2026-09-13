ALTER TABLE orders
    ADD COLUMN client_order_id uuid,
    ADD COLUMN request_hash text CHECK (request_hash IS NULL OR request_hash ~ '^[0-9a-f]{64}$');

CREATE UNIQUE INDEX orders_source_client_order_uidx
    ON orders (source, client_order_id) WHERE client_order_id IS NOT NULL;
