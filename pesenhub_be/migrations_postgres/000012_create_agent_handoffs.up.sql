ALTER TABLE agent_conversations DROP CONSTRAINT IF EXISTS agent_conversations_status_check;
ALTER TABLE agent_conversations ADD CONSTRAINT agent_conversations_status_check CHECK (status IN ('COLLECTING', 'AWAITING_CLARIFICATION', 'READY_FOR_CONFIRMATION', 'HANDOFF', 'PAUSED'));

ALTER TABLE agent_conversations
    ADD COLUMN is_paused boolean NOT NULL DEFAULT false,
    ADD COLUMN paused_by text,
    ADD COLUMN paused_at timestamptz,
    ADD COLUMN paused_reason text,
    ADD COLUMN resumed_by text,
    ADD COLUMN resumed_at timestamptz,
    ADD COLUMN handoff_status text NOT NULL DEFAULT 'NONE' CHECK (handoff_status IN ('NONE', 'PENDING', 'ASSIGNED', 'RESOLVED')),
    ADD COLUMN handoff_reason text,
    ADD COLUMN handoff_priority text NOT NULL DEFAULT 'NORMAL' CHECK (handoff_priority IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
    ADD COLUMN assigned_to text,
    ADD COLUMN assigned_at timestamptz,
    ADD COLUMN resolved_at timestamptz,
    ADD COLUMN tool_failure_count integer NOT NULL DEFAULT 0;

CREATE INDEX idx_agent_conversations_handoff_queue ON agent_conversations (handoff_status, handoff_priority, updated_at);

CREATE TABLE agent_conversation_audits (
    id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES agent_conversations(id) ON DELETE CASCADE,
    session text NOT NULL,
    customer_phone text NOT NULL,
    action text NOT NULL CHECK (action IN ('HANDOFF_TRIGGERED', 'PAUSED', 'RESUMED', 'ASSIGNED', 'RESOLVED')),
    actor text NOT NULL,
    actor_role text NOT NULL DEFAULT 'STAFF' CHECK (actor_role IN ('SYSTEM', 'STAFF', 'ADMIN')),
    reason text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    correlation_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_agent_conversation_audits_conv ON agent_conversation_audits (conversation_id, created_at);
CREATE INDEX idx_agent_conversation_audits_created ON agent_conversation_audits (created_at);
