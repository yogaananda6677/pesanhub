CREATE TABLE customers (
    id uuid PRIMARY KEY,
    phone_e164 text NOT NULL UNIQUE CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
    display_name text NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 120),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE menu_categories (
    id uuid PRIMARY KEY,
    name text NOT NULL UNIQUE CHECK (char_length(btrim(name)) BETWEEN 1 AND 100),
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE menus (
    id uuid PRIMARY KEY,
    category_id uuid NOT NULL REFERENCES menu_categories(id) ON DELETE RESTRICT,
    sku text NOT NULL UNIQUE CHECK (char_length(btrim(sku)) BETWEEN 1 AND 64),
    name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 160),
    description text,
    price_amount bigint NOT NULL CHECK (price_amount >= 0),
    is_available boolean NOT NULL DEFAULT true,
    version bigint NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX menus_category_available_idx ON menus (category_id, is_available, id);

CREATE TABLE menu_modifiers (
    id uuid PRIMARY KEY,
    menu_id uuid NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
    code text NOT NULL,
    name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
    price_delta_amount bigint NOT NULL DEFAULT 0,
    is_available boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (menu_id, code)
);

CREATE TABLE orders (
    id uuid PRIMARY KEY,
    order_number text NOT NULL UNIQUE,
    customer_id uuid REFERENCES customers(id) ON DELETE RESTRICT,
    source text NOT NULL CHECK (source IN ('WHATSAPP', 'CASHIER_MANUAL', 'CUSTOMER_WEB')),
    fulfillment text NOT NULL DEFAULT 'PICKUP' CHECK (fulfillment IN ('PICKUP')),
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'COMPLETED', 'REJECTED', 'CANCELLED')),
    channel_reference text,
    customer_name_snapshot text NOT NULL CHECK (char_length(btrim(customer_name_snapshot)) BETWEEN 1 AND 120),
    customer_phone_snapshot text CHECK (customer_phone_snapshot IS NULL OR customer_phone_snapshot ~ '^\+[1-9][0-9]{7,14}$'),
    notes text,
    subtotal_amount bigint NOT NULL CHECK (subtotal_amount >= 0),
    total_amount bigint NOT NULL CHECK (total_amount >= 0 AND total_amount = subtotal_amount),
    idempotency_key text NOT NULL CHECK (char_length(idempotency_key) BETWEEN 1 AND 128),
    version bigint NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source, idempotency_key)
);
CREATE INDEX orders_queue_idx ON orders (status, created_at, id);
CREATE INDEX orders_customer_idx ON orders (customer_id, created_at DESC, id DESC);
CREATE UNIQUE INDEX orders_channel_reference_uidx ON orders (source, channel_reference) WHERE channel_reference IS NOT NULL;

CREATE TABLE order_items (
    id uuid PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    menu_id uuid REFERENCES menus(id) ON DELETE SET NULL,
    menu_name_snapshot text NOT NULL,
    sku_snapshot text NOT NULL,
    unit_price_amount bigint NOT NULL CHECK (unit_price_amount >= 0),
    quantity integer NOT NULL CHECK (quantity > 0),
    line_total_amount bigint NOT NULL CHECK (line_total_amount >= 0),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX order_items_order_idx ON order_items (order_id, id);

CREATE TABLE order_item_modifiers (
    id uuid PRIMARY KEY,
    order_item_id uuid NOT NULL REFERENCES order_items(id) ON DELETE RESTRICT,
    menu_modifier_id uuid REFERENCES menu_modifiers(id) ON DELETE SET NULL,
    name_snapshot text NOT NULL,
    price_delta_amount bigint NOT NULL,
    quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE order_status_history (
    id uuid PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    from_status text CHECK (from_status IS NULL OR from_status IN ('PENDING', 'ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'COMPLETED', 'REJECTED', 'CANCELLED')),
    to_status text NOT NULL CHECK (to_status IN ('PENDING', 'ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'COMPLETED', 'REJECTED', 'CANCELLED')),
    order_version bigint NOT NULL CHECK (order_version >= 1),
    actor_type text NOT NULL CHECK (actor_type IN ('STAFF', 'CUSTOMER', 'SYSTEM', 'AGENT')),
    actor_id text,
    reason_code text,
    request_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (order_id, order_version)
);
CREATE INDEX order_status_history_order_idx ON order_status_history (order_id, created_at, id);

CREATE TABLE payments (
    id uuid PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    method text NOT NULL CHECK (method IN ('CASH', 'MIDTRANS_QRIS')),
    status text NOT NULL CHECK (status IN ('UNPAID', 'PENDING_PAYMENT', 'PAID', 'FAILED', 'EXPIRED', 'REFUNDED')),
    amount bigint NOT NULL CHECK (amount >= 0),
    provider_reference text UNIQUE,
    idempotency_key text NOT NULL UNIQUE CHECK (char_length(idempotency_key) BETWEEN 1 AND 128),
    version bigint NOT NULL DEFAULT 1 CHECK (version >= 1),
    paid_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((status = 'PAID' AND paid_at IS NOT NULL) OR status <> 'PAID')
);
CREATE INDEX payments_order_idx ON payments (order_id, created_at, id);

CREATE TABLE payment_events (
    id uuid PRIMARY KEY,
    payment_id uuid NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
    provider text NOT NULL CHECK (provider IN ('CASH', 'MIDTRANS')),
    provider_event_id text NOT NULL,
    event_type text NOT NULL,
    payload_redacted jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload_redacted) = 'object'),
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    UNIQUE (provider, provider_event_id)
);

CREATE TABLE audit_logs (
    id uuid PRIMARY KEY,
    aggregate_type text NOT NULL,
    aggregate_id uuid NOT NULL,
    action text NOT NULL,
    actor_type text NOT NULL CHECK (actor_type IN ('STAFF', 'CUSTOMER', 'SYSTEM', 'AGENT')),
    actor_id text,
    request_id text NOT NULL,
    metadata_redacted jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata_redacted) = 'object'),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_aggregate_idx ON audit_logs (aggregate_type, aggregate_id, created_at, id);

CREATE TABLE outbox_events (
    id uuid PRIMARY KEY,
    aggregate_type text NOT NULL,
    aggregate_id uuid NOT NULL,
    event_type text NOT NULL,
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    deduplication_key text NOT NULL UNIQUE,
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'PUBLISHED', 'FAILED')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    last_error_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX outbox_events_dispatch_idx ON outbox_events (status, available_at, id) WHERE status IN ('PENDING', 'FAILED');
