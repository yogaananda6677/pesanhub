DROP INDEX IF EXISTS idx_agent_conversations_last_order;

ALTER TABLE agent_conversations
    DROP COLUMN IF EXISTS last_order_id,
    DROP COLUMN IF EXISTS draft_version,
    DROP COLUMN IF EXISTS confirmation_token;

ALTER TABLE agent_conversations DROP CONSTRAINT IF EXISTS agent_conversations_status_check;
ALTER TABLE agent_conversations ADD CONSTRAINT agent_conversations_status_check CHECK (status IN ('COLLECTING', 'AWAITING_CLARIFICATION', 'READY_FOR_CONFIRMATION', 'HANDOFF', 'PAUSED'));
