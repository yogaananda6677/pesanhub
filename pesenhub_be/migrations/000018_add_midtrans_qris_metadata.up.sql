ALTER TABLE payments
    ADD COLUMN provider_order_id text UNIQUE,
    ADD COLUMN qr_code_url text,
    ADD COLUMN expires_at timestamptz,
    ADD COLUMN provider_attempt_state text CHECK (provider_attempt_state IS NULL OR provider_attempt_state IN ('IN_FLIGHT', 'UNKNOWN', 'SUCCEEDED', 'PERMANENT_FAILURE')),
    ADD COLUMN provider_attempt_count integer NOT NULL DEFAULT 0 CHECK (provider_attempt_count >= 0),
    ADD COLUMN provider_last_attempt_at timestamptz,
    ADD COLUMN provider_error_code text,
    ADD COLUMN provider_response_redacted jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(provider_response_redacted) = 'object');

CREATE UNIQUE INDEX payments_one_midtrans_qris_per_order_idx
    ON payments (order_id)
    WHERE method = 'MIDTRANS_QRIS';
