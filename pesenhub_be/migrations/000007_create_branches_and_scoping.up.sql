-- 000007_create_branches_and_scoping.up.sql

-- 1. Create branches table
CREATE TABLE branches (
  id char(36) PRIMARY KEY,
  code varchar(32) NOT NULL,
  name varchar(120) NOT NULL,
  address text,
  phone varchar(32),
  is_default boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_branches_code (code),
  INDEX branches_active_idx (is_active, id)
) ENGINE=InnoDB;

-- 2. Insert default branch (Cabang Utama Banyuwangi)
INSERT INTO branches (id, code, name, address, phone, is_default, is_active)
VALUES (
  'b0000000-0000-0000-0000-000000000001',
  'BWX',
  'Cabang Utama Banyuwangi',
  'Jl. Ahmad Yani No. 45, Banyuwangi',
  '+6281234567890',
  true,
  true
)
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- 3. Update app_users with branch_id
ALTER TABLE app_users
  ADD COLUMN branch_id char(36) NULL AFTER role,
  ADD CONSTRAINT fk_app_users_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL,
  ADD INDEX app_users_branch_idx (branch_id);

-- Backfill existing CASHIER users to default branch (ADMIN remains NULL for multi-branch access)
UPDATE app_users
SET branch_id = 'b0000000-0000-0000-0000-000000000001'
WHERE role = 'CASHIER' AND branch_id IS NULL;

-- 4. Update orders with branch_id
ALTER TABLE orders
  ADD COLUMN branch_id char(36) NULL AFTER id;

-- Backfill all existing orders to default branch
UPDATE orders
SET branch_id = 'b0000000-0000-0000-0000-000000000001'
WHERE branch_id IS NULL;

-- Make branch_id NOT NULL and add foreign key & composite indexes
ALTER TABLE orders
  MODIFY COLUMN branch_id char(36) NOT NULL,
  ADD CONSTRAINT fk_orders_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE RESTRICT,
  ADD INDEX orders_branch_created_idx (branch_id, created_at, id),
  ADD INDEX orders_branch_status_idx (branch_id, status, created_at, id);

-- 5. Update user_invitations with branch_id
ALTER TABLE user_invitations
  ADD COLUMN branch_id char(36) NULL AFTER outlet_name,
  ADD CONSTRAINT fk_user_invitations_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL,
  ADD INDEX user_invitations_branch_idx (branch_id);

-- Backfill existing invitations to default branch
UPDATE user_invitations
SET branch_id = 'b0000000-0000-0000-0000-000000000001'
WHERE branch_id IS NULL;

-- 6. Create branch_menu_availability
CREATE TABLE branch_menu_availability (
  branch_id char(36) NOT NULL,
  menu_id char(36) NOT NULL,
  is_available boolean NOT NULL DEFAULT true,
  version bigint NOT NULL DEFAULT 1,
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (branch_id, menu_id),
  CONSTRAINT fk_bma_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
  CONSTRAINT fk_bma_menu FOREIGN KEY (menu_id) REFERENCES menus(id) ON DELETE CASCADE,
  INDEX bma_branch_avail_idx (branch_id, is_available)
) ENGINE=InnoDB;

-- Backfill menu availability for all branches from menus.is_available
INSERT IGNORE INTO branch_menu_availability (branch_id, menu_id, is_available, version)
SELECT b.id, m.id, m.is_available, 1
FROM branches b
CROSS JOIN menus m;

-- 7. Create branch_modifier_option_availability
CREATE TABLE branch_modifier_option_availability (
  branch_id char(36) NOT NULL,
  modifier_option_id char(36) NOT NULL,
  is_available boolean NOT NULL DEFAULT true,
  version bigint NOT NULL DEFAULT 1,
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (branch_id, modifier_option_id),
  CONSTRAINT fk_bmoa_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
  CONSTRAINT fk_bmoa_option FOREIGN KEY (modifier_option_id) REFERENCES modifier_options(id) ON DELETE CASCADE,
  INDEX bmoa_branch_avail_idx (branch_id, is_available)
) ENGINE=InnoDB;

-- Backfill modifier option availability for all branches from modifier_options.is_available
INSERT IGNORE INTO branch_modifier_option_availability (branch_id, modifier_option_id, is_available, version)
SELECT b.id, o.id, o.is_available, 1
FROM branches b
CROSS JOIN modifier_options o;

-- 8. WhatsApp / Agent conversations branch scoping
ALTER TABLE agent_conversations
  ADD COLUMN branch_id char(36) NULL AFTER session,
  ADD CONSTRAINT fk_agent_conversations_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL,
  ADD INDEX agent_conversations_branch_idx (branch_id);

UPDATE agent_conversations
SET branch_id = 'b0000000-0000-0000-0000-000000000001'
WHERE branch_id IS NULL;

ALTER TABLE whatsapp_inbound_messages
  ADD COLUMN branch_id char(36) NULL AFTER session_id,
  ADD CONSTRAINT fk_whatsapp_inbound_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL,
  ADD INDEX whatsapp_inbound_branch_idx (branch_id);

UPDATE whatsapp_inbound_messages
SET branch_id = 'b0000000-0000-0000-0000-000000000001'
WHERE branch_id IS NULL;

-- 9. Update schema metadata
UPDATE app_metadata
SET `value` = 'mysql-branches-scoping-v3'
WHERE `key` = 'schema_foundation';
