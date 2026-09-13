ALTER TABLE agent_conversations DROP CONSTRAINT IF EXISTS agent_conversations_status_check;
ALTER TABLE agent_conversations ADD CONSTRAINT agent_conversations_status_check CHECK (status IN ('COLLECTING', 'AWAITING_CLARIFICATION', 'READY_FOR_CONFIRMATION', 'HANDOFF', 'PAUSED', 'COMPLETED'));

ALTER TABLE agent_conversations
    ADD COLUMN IF NOT EXISTS confirmation_token text,
    ADD COLUMN IF NOT EXISTS draft_version integer NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS last_order_id uuid REFERENCES orders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_agent_conversations_last_order ON agent_conversations (last_order_id);
