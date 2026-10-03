-- 000007_create_branches_and_scoping.down.sql

ALTER TABLE whatsapp_inbound_messages
  DROP FOREIGN KEY fk_whatsapp_inbound_branch,
  DROP INDEX whatsapp_inbound_branch_idx,
  DROP COLUMN branch_id;

ALTER TABLE agent_conversations
  DROP FOREIGN KEY fk_agent_conversations_branch,
  DROP INDEX agent_conversations_branch_idx,
  DROP COLUMN branch_id;

DROP TABLE IF EXISTS branch_modifier_option_availability;
DROP TABLE IF EXISTS branch_menu_availability;

ALTER TABLE user_invitations
  DROP FOREIGN KEY fk_user_invitations_branch,
  DROP INDEX user_invitations_branch_idx,
  DROP COLUMN branch_id;

ALTER TABLE orders
  DROP FOREIGN KEY fk_orders_branch,
  DROP INDEX orders_branch_created_idx,
  DROP INDEX orders_branch_status_idx,
  DROP COLUMN branch_id;

ALTER TABLE app_users
  DROP FOREIGN KEY fk_app_users_branch,
  DROP INDEX app_users_branch_idx,
  DROP COLUMN branch_id;

DROP TABLE IF EXISTS branches;

UPDATE app_metadata
SET `value` = 'mysql-admin-cashier-auth-v2'
WHERE `key` = 'schema_foundation';
