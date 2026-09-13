CREATE TABLE app_metadata (
    key text PRIMARY KEY,
    value text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO app_metadata (key, value) VALUES ('schema_foundation', 'phase-0');
