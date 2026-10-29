CREATE TABLE IF NOT EXISTS agent_conversation_contexts (
  id VARCHAR(36) PRIMARY KEY,
  conversation_id VARCHAR(36) NOT NULL,
  session VARCHAR(191) NOT NULL,
  customer_phone VARCHAR(20) NOT NULL,
  cycle_id VARCHAR(36) NOT NULL,
  role VARCHAR(16) NOT NULL,
  message_text TEXT NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_conv_context_cycle (customer_phone, cycle_id, created_at),
  INDEX idx_conv_context_conv (conversation_id, created_at)
) ENGINE=InnoDB;
