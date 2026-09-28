UPDATE app_users SET role = 'ADMIN' WHERE role = 'OWNER';

ALTER TABLE user_invitations
  ADD COLUMN role varchar(16) NOT NULL DEFAULT 'CASHIER' AFTER outlet_name,
  ADD COLUMN accepted_user_id char(36) NULL AFTER expires_at,
  ADD COLUMN accepted_at datetime(6) NULL AFTER accepted_user_id,
  ADD CONSTRAINT fk_user_invitations_accepted_user
    FOREIGN KEY (accepted_user_id) REFERENCES app_users(id) ON DELETE SET NULL,
  ADD INDEX user_invitations_role_status_idx (role, status, expires_at);

UPDATE app_metadata
SET `value` = 'mysql-admin-cashier-auth-v2'
WHERE `key` = 'schema_foundation';
