UPDATE app_users SET role = 'OWNER' WHERE role IN ('ADMIN', 'CASHIER');

ALTER TABLE user_invitations
  DROP FOREIGN KEY fk_user_invitations_accepted_user,
  DROP INDEX user_invitations_role_status_idx,
  DROP COLUMN accepted_at,
  DROP COLUMN accepted_user_id,
  DROP COLUMN role;

UPDATE app_metadata
SET `value` = 'mysql-baseline-v1'
WHERE `key` = 'schema_foundation';
