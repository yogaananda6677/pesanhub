CREATE TABLE user_invitations (
    id uuid PRIMARY KEY,
    email_normalized text NOT NULL UNIQUE CHECK (email_normalized = lower(btrim(email_normalized)) AND char_length(email_normalized) BETWEEN 3 AND 320),
    invited_by uuid NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
    outlet_name text NOT NULL DEFAULT 'PesenHub Outlet #01' CHECK (char_length(btrim(outlet_name)) BETWEEN 1 AND 120),
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED')),
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at)
);

CREATE INDEX user_invitations_status_idx ON user_invitations (status, expires_at);

CREATE TABLE system_traffic_samples (
    bucket_time timestamptz NOT NULL PRIMARY KEY,
    total_requests integer NOT NULL DEFAULT 0 CHECK (total_requests >= 0),
    success_requests integer NOT NULL DEFAULT 0 CHECK (success_requests >= 0),
    client_errors integer NOT NULL DEFAULT 0 CHECK (client_errors >= 0),
    server_errors integer NOT NULL DEFAULT 0 CHECK (server_errors >= 0),
    latency_p50_ms integer NOT NULL DEFAULT 0 CHECK (latency_p50_ms >= 0),
    latency_p95_ms integer NOT NULL DEFAULT 0 CHECK (latency_p95_ms >= 0),
    wa_inbound_count integer NOT NULL DEFAULT 0 CHECK (wa_inbound_count >= 0),
    wa_outbound_count integer NOT NULL DEFAULT 0 CHECK (wa_outbound_count >= 0),
    sync_success_count integer NOT NULL DEFAULT 0 CHECK (sync_success_count >= 0),
    sync_failure_count integer NOT NULL DEFAULT 0 CHECK (sync_failure_count >= 0),
    sync_conflict_count integer NOT NULL DEFAULT 0 CHECK (sync_conflict_count >= 0)
);

CREATE INDEX system_traffic_samples_time_idx ON system_traffic_samples (bucket_time DESC);
