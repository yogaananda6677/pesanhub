DROP INDEX IF EXISTS orders_source_client_order_uidx;
ALTER TABLE orders DROP COLUMN request_hash, DROP COLUMN client_order_id;
