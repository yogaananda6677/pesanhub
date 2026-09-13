DROP TABLE IF EXISTS agent_conversation_audits;

DROP INDEX IF EXISTS idx_agent_conversations_handoff_queue;

ALTER TABLE agent_conversations
    DROP COLUMN IF EXISTS is_paused,
    DROP COLUMN IF EXISTS paused_by,
    DROP COLUMN IF EXISTS paused_at,
    DROP COLUMN IF EXISTS paused_reason,
    DROP COLUMN IF EXISTS resumed_by,
    DROP COLUMN IF EXISTS resumed_at,
    DROP COLUMN IF EXISTS handoff_status,
    DROP COLUMN IF EXISTS handoff_reason,
    DROP COLUMN IF EXISTS handoff_priority,
    DROP COLUMN IF EXISTS assigned_to,
    DROP COLUMN IF EXISTS assigned_at,
    DROP COLUMN IF EXISTS resolved_at,
    DROP COLUMN IF EXISTS tool_failure_count;

ALTER TABLE agent_conversations DROP CONSTRAINT IF EXISTS agent_conversations_status_check;
ALTER TABLE agent_conversations ADD CONSTRAINT agent_conversations_status_check CHECK (status IN ('COLLECTING', 'AWAITING_CLARIFICATION', 'READY_FOR_CONFIRMATION', 'HANDOFF'));
