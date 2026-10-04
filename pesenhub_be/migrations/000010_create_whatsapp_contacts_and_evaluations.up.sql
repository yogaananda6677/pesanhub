-- 000010_create_whatsapp_contacts_and_evaluations.up.sql

-- 1. Create whatsapp_contacts table
CREATE TABLE whatsapp_contacts (
  id char(36) PRIMARY KEY,
  branch_id char(36) NOT NULL,
  phone_e164 varchar(16) NOT NULL UNIQUE,
  name varchar(120) NULL,
  contact_type varchar(32) NOT NULL DEFAULT 'CUSTOMER',
  auto_reply_enabled boolean NOT NULL DEFAULT true,
  notes text NULL,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_whatsapp_contacts_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
  INDEX idx_whatsapp_contacts_branch_type (branch_id, contact_type, auto_reply_enabled),
  INDEX idx_whatsapp_contacts_phone (phone_e164)
) ENGINE=InnoDB;

-- 2. Create ai_evaluations table
CREATE TABLE ai_evaluations (
  id char(36) PRIMARY KEY,
  branch_id char(36) NOT NULL,
  inbound_message_id char(36) NULL,
  conversation_id char(36) NULL,
  sender_phone varchar(16) NOT NULL,
  customer_name varchar(120) NULL,
  input_text text NOT NULL,
  ai_reply text NOT NULL,
  extracted_draft json NOT NULL DEFAULT (JSON_OBJECT()),
  rating varchar(16) NOT NULL DEFAULT 'UNRATED',
  feedback_category varchar(64) NULL,
  correction_notes text NULL,
  expected_reply text NULL,
  is_reviewed boolean NOT NULL DEFAULT false,
  reviewed_by varchar(191) NULL,
  reviewed_at datetime(6) NULL,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_ai_evaluations_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
  CONSTRAINT fk_ai_evaluations_inbound FOREIGN KEY (inbound_message_id) REFERENCES whatsapp_inbound_messages(id) ON DELETE SET NULL,
  CONSTRAINT fk_ai_evaluations_conv FOREIGN KEY (conversation_id) REFERENCES agent_conversations(id) ON DELETE SET NULL,
  INDEX idx_ai_evaluations_branch_reviewed (branch_id, is_reviewed, rating, created_at),
  INDEX idx_ai_evaluations_phone (sender_phone, created_at)
) ENGINE=InnoDB;
