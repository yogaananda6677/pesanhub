CREATE TABLE waha_inbound_messages (
    id uuid PRIMARY KEY,
    provider_message_id text NOT NULL UNIQUE,
    webhook_request_id text,
    session text NOT NULL,
    event_type text NOT NULL,
    from_raw text NOT NULL,
    phone_e164 text CHECK (phone_e164 IS NULL OR phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
    sender_name text CHECK (sender_name IS NULL OR char_length(btrim(sender_name)) <= 120),
    message_body text,
    payload_redacted jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'RECEIVED' CHECK (status IN ('RECEIVED', 'PROCESSED', 'DUPLICATE', 'QUARANTINED', 'FAILED')),
    quarantine_reason text,
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX waha_inbound_messages_status_received_idx ON waha_inbound_messages (status, received_at);
CREATE INDEX waha_inbound_messages_phone_idx ON waha_inbound_messages (phone_e164) WHERE phone_e164 IS NOT NULL;
