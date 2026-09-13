ALTER TABLE payments
    ADD COLUMN request_hash text,
    ADD COLUMN actor_id text,
    ADD COLUMN request_id text;

CREATE UNIQUE INDEX payments_one_cash_per_order_idx
    ON payments (order_id)
    WHERE method = 'CASH';

