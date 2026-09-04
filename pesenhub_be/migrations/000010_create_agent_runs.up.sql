CREATE TABLE agent_runs (
    id uuid PRIMARY KEY,
    inbound_message_id uuid REFERENCES waha_inbound_messages(id) ON DELETE SET NULL,
    session text NOT NULL,
    customer_phone text,
    model text NOT NULL,
    prompt_version text NOT NULL,
    confidence_score numeric(3, 2) NOT NULL CHECK (confidence_score >= 0.0 AND confidence_score <= 1.0),
    is_ambiguous boolean NOT NULL DEFAULT false,
    ambiguity_reasons text[],
    extracted_draft jsonb NOT NULL DEFAULT '{}'::jsonb,
    tool_calls jsonb NOT NULL DEFAULT '[]'::jsonb,
    duration_ms integer NOT NULL DEFAULT 0,
    status text NOT NULL CHECK (status IN ('SUCCESS', 'AMBIGUOUS', 'FAILED', 'REJECTED_INJECTION')),
    error_message text,
    correlation_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX agent_runs_correlation_idx ON agent_runs (correlation_id);
CREATE INDEX agent_runs_status_created_idx ON agent_runs (status, created_at);
CREATE INDEX agent_runs_inbound_message_idx ON agent_runs (inbound_message_id) WHERE inbound_message_id IS NOT NULL;
