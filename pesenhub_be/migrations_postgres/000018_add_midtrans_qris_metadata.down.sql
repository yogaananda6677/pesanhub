DROP INDEX IF EXISTS payments_one_midtrans_qris_per_order_idx;

ALTER TABLE payments
    DROP COLUMN IF EXISTS provider_response_redacted,
    DROP COLUMN IF EXISTS provider_error_code,
    DROP COLUMN IF EXISTS provider_last_attempt_at,
    DROP COLUMN IF EXISTS provider_attempt_count,
    DROP COLUMN IF EXISTS provider_attempt_state,
    DROP COLUMN IF EXISTS expires_at,
    DROP COLUMN IF EXISTS qr_code_url,
    DROP COLUMN IF EXISTS provider_order_id;
