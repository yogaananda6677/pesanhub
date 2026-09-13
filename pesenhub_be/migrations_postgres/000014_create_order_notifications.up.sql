CREATE TABLE customer_opt_outs (
    id uuid PRIMARY KEY,
    phone_e164 text NOT NULL UNIQUE CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
    reason text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_customer_opt_outs_phone ON customer_opt_outs (phone_e164);

CREATE TABLE order_notifications (
    id uuid PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    customer_phone text NOT NULL,
    notification_type text NOT NULL CHECK (notification_type IN ('CONFIRMATION', 'ACCEPTED', 'COMPLETED')),
    template_version text NOT NULL DEFAULT 'v1',
    idempotency_key text NOT NULL UNIQUE,
    message_text text NOT NULL,
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'SUPPRESSED')),
    suppress_reason text CHECK (suppress_reason IS NULL OR suppress_reason IN ('CUSTOMER_OPTED_OUT', 'CONVERSATION_PAUSED', 'HANDOFF_ACTIVE')),
    provider_message_id text,
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error text,
    sent_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_notifications_order_type ON order_notifications (order_id, notification_type);
CREATE INDEX idx_order_notifications_status ON order_notifications (status, created_at);
