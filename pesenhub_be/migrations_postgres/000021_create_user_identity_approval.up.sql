CREATE TABLE app_users (
    id uuid PRIMARY KEY,
    email_normalized text NOT NULL UNIQUE CHECK (email_normalized = lower(btrim(email_normalized)) AND char_length(email_normalized) BETWEEN 3 AND 320),
    display_name text NOT NULL DEFAULT '' CHECK (char_length(display_name) <= 160),
    role text NOT NULL CHECK (role IN ('OWNER', 'SUPERADMIN')),
    status text NOT NULL DEFAULT 'PENDING_APPROVAL' CHECK (status IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'SUSPENDED')),
    approved_by uuid REFERENCES app_users(id) ON DELETE RESTRICT,
    status_reason text CHECK (status_reason IS NULL OR char_length(status_reason) <= 500),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((status = 'APPROVED' AND approved_at IS NOT NULL) OR status <> 'APPROVED')
);

CREATE TABLE external_identities (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    provider text NOT NULL CHECK (provider IN ('GOOGLE')),
    provider_subject text NOT NULL CHECK (char_length(provider_subject) BETWEEN 1 AND 255),
    email_at_login text NOT NULL CHECK (char_length(email_at_login) BETWEEN 3 AND 320),
    created_at timestamptz NOT NULL DEFAULT now(),
    last_login_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_subject),
    UNIQUE (provider, user_id)
);

CREATE TABLE app_sessions (
    id text PRIMARY KEY CHECK (char_length(id) BETWEEN 20 AND 128),
    user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at)
);
CREATE INDEX app_sessions_user_active_idx ON app_sessions (user_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE user_status_audits (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
    actor_user_id uuid REFERENCES app_users(id) ON DELETE RESTRICT,
    from_status text CHECK (from_status IS NULL OR from_status IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'SUSPENDED')),
    to_status text NOT NULL CHECK (to_status IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'SUSPENDED')),
    reason_redacted text CHECK (reason_redacted IS NULL OR char_length(reason_redacted) <= 500),
    request_id text NOT NULL CHECK (char_length(request_id) BETWEEN 1 AND 128),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX user_status_audits_user_idx ON user_status_audits (user_id, created_at, id);
