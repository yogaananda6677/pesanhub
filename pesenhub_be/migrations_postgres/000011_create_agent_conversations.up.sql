CREATE TABLE agent_conversations (
    id uuid PRIMARY KEY,
    session text NOT NULL,
    customer_phone text NOT NULL,
    status text NOT NULL DEFAULT 'COLLECTING' CHECK (status IN ('COLLECTING', 'AWAITING_CLARIFICATION', 'READY_FOR_CONFIRMATION', 'HANDOFF')),
    current_draft jsonb NOT NULL DEFAULT '{}'::jsonb,
    pending_ambiguity text,
    clarification_attempts integer NOT NULL DEFAULT 0,
    last_question text,
    last_inbound_message_id uuid REFERENCES waha_inbound_messages(id) ON DELETE SET NULL,
    correlation_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX agent_conversations_session_phone_idx ON agent_conversations (session, customer_phone);
CREATE INDEX agent_conversations_status_idx ON agent_conversations (status);
