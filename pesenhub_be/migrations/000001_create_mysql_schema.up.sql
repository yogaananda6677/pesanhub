CREATE TABLE app_metadata (
  `key` varchar(191) PRIMARY KEY, `value` text NOT NULL,
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

CREATE TABLE advisory_locks (
  lock_key varchar(191) PRIMARY KEY
) ENGINE=InnoDB;

CREATE TABLE customers (
  id char(36) PRIMARY KEY, phone_e164 varchar(16) NOT NULL UNIQUE, display_name varchar(120) NOT NULL, notes text,
  preferences json NOT NULL DEFAULT (JSON_OBJECT()), version bigint NOT NULL DEFAULT 1, create_idempotency_key varchar(128) UNIQUE,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CHECK (version >= 1)
) ENGINE=InnoDB;

CREATE TABLE menu_categories (
  id char(36) PRIMARY KEY, name varchar(100) NOT NULL UNIQUE, sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true, version bigint NOT NULL DEFAULT 1,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CHECK (sort_order >= 0), CHECK (version >= 1)
) ENGINE=InnoDB;

CREATE TABLE menus (
  id char(36) PRIMARY KEY, category_id char(36) NOT NULL, sku varchar(64) NOT NULL UNIQUE, name varchar(160) NOT NULL,
  description text, price_amount bigint NOT NULL, is_available boolean NOT NULL DEFAULT true, version bigint NOT NULL DEFAULT 1,
  sort_order int NOT NULL DEFAULT 0, created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  FOREIGN KEY (category_id) REFERENCES menu_categories(id) ON DELETE RESTRICT,
  CHECK (price_amount >= 0), CHECK (version >= 1), CHECK (sort_order >= 0),
  INDEX menus_category_available_idx (category_id, is_available, id), INDEX menus_public_order_idx (category_id, is_available, sort_order, name, id)
) ENGINE=InnoDB;

CREATE TABLE menu_modifiers (
  id char(36) PRIMARY KEY, menu_id char(36) NOT NULL, code varchar(64) NOT NULL, name varchar(120) NOT NULL,
  price_delta_amount bigint NOT NULL DEFAULT 0, is_available boolean NOT NULL DEFAULT true, sort_order int NOT NULL DEFAULT 0,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_menu_modifiers_menu_code (menu_id, code), FOREIGN KEY (menu_id) REFERENCES menus(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE modifier_groups (
  id char(36) PRIMARY KEY, menu_id char(36) NOT NULL, code varchar(64) NOT NULL, name varchar(120) NOT NULL,
  min_select int NOT NULL DEFAULT 0, max_select int NOT NULL DEFAULT 1, is_active boolean NOT NULL DEFAULT true, sort_order int NOT NULL DEFAULT 0,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_modifier_groups_menu_code (menu_id, code), INDEX modifier_groups_menu_idx (menu_id, sort_order, id),
  FOREIGN KEY (menu_id) REFERENCES menus(id) ON DELETE CASCADE, CHECK (min_select >= 0 AND max_select >= 1 AND max_select >= min_select)
) ENGINE=InnoDB;

CREATE TABLE modifier_options (
  id char(36) PRIMARY KEY, group_id char(36) NOT NULL, code varchar(64) NOT NULL, name varchar(120) NOT NULL,
  price_delta_amount bigint NOT NULL DEFAULT 0, is_available boolean NOT NULL DEFAULT true, sort_order int NOT NULL DEFAULT 0,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_modifier_options_group_code (group_id, code), INDEX modifier_options_group_idx (group_id, sort_order, id),
  FOREIGN KEY (group_id) REFERENCES modifier_groups(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE orders (
  id char(36) PRIMARY KEY, order_number varchar(64) NOT NULL UNIQUE, customer_id char(36), source varchar(32) NOT NULL,
  fulfillment varchar(16) NOT NULL DEFAULT 'PICKUP', status varchar(32) NOT NULL DEFAULT 'PENDING', channel_reference varchar(191),
  customer_name_snapshot varchar(120) NOT NULL, customer_phone_snapshot varchar(16), notes text,
  subtotal_amount bigint NOT NULL, total_amount bigint NOT NULL, idempotency_key varchar(128) NOT NULL,
  client_order_id char(36), request_hash char(64), public_tracking_token varchar(191) UNIQUE, version bigint NOT NULL DEFAULT 1,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
  UNIQUE KEY uq_orders_source_idempotency (source, idempotency_key), UNIQUE KEY uq_orders_source_channel (source, channel_reference),
  UNIQUE KEY uq_orders_source_client (source, client_order_id), INDEX orders_queue_idx (status, created_at, id),
  INDEX orders_customer_idx (customer_id, created_at DESC, id DESC), INDEX orders_source_status_created_idx (source, status, created_at, id),
  INDEX orders_created_at_idx (created_at, id), CHECK (subtotal_amount >= 0), CHECK (total_amount = subtotal_amount), CHECK (version >= 1)
) ENGINE=InnoDB;

CREATE TABLE order_items (
  id char(36) PRIMARY KEY, order_id char(36) NOT NULL, menu_id char(36), menu_name_snapshot varchar(160) NOT NULL,
  sku_snapshot varchar(64) NOT NULL, unit_price_amount bigint NOT NULL, quantity int NOT NULL, line_total_amount bigint NOT NULL, notes text,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT,
  FOREIGN KEY (menu_id) REFERENCES menus(id) ON DELETE SET NULL, INDEX order_items_order_idx (order_id, id),
  CHECK (unit_price_amount >= 0), CHECK (quantity > 0), CHECK (line_total_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE order_item_modifiers (
  id char(36) PRIMARY KEY, order_item_id char(36) NOT NULL, menu_modifier_id char(36), modifier_option_id char(36),
  name_snapshot varchar(120) NOT NULL, price_delta_amount bigint NOT NULL, quantity int NOT NULL DEFAULT 1,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), FOREIGN KEY (order_item_id) REFERENCES order_items(id) ON DELETE RESTRICT,
  FOREIGN KEY (menu_modifier_id) REFERENCES menu_modifiers(id) ON DELETE SET NULL,
  FOREIGN KEY (modifier_option_id) REFERENCES modifier_options(id) ON DELETE SET NULL, INDEX order_item_modifiers_item_idx (order_item_id), CHECK (quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE order_status_history (
  id char(36) PRIMARY KEY, order_id char(36) NOT NULL, from_status varchar(32), to_status varchar(32) NOT NULL,
  order_version bigint NOT NULL, actor_type varchar(16) NOT NULL, actor_id varchar(191), reason_code varchar(191), request_id varchar(128) NOT NULL,
  idempotency_key varchar(128), request_hash char(64), created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT, UNIQUE KEY uq_order_history_version (order_id, order_version),
  UNIQUE KEY uq_order_history_idempotency (order_id, idempotency_key), INDEX order_status_history_order_idx (order_id, created_at, id)
) ENGINE=InnoDB;

CREATE TABLE payments (
  id char(36) PRIMARY KEY, order_id char(36) NOT NULL, method varchar(32) NOT NULL, status varchar(32) NOT NULL, amount bigint NOT NULL,
  provider_reference varchar(191) UNIQUE, idempotency_key varchar(128) NOT NULL UNIQUE, version bigint NOT NULL DEFAULT 1, paid_at datetime(6),
  request_hash char(64), actor_id varchar(191), request_id varchar(128), provider_order_id varchar(191) UNIQUE, qr_code_url text, expires_at datetime(6),
  provider_attempt_state varchar(32), provider_attempt_count int NOT NULL DEFAULT 0, provider_last_attempt_at datetime(6), provider_error_code varchar(191),
  provider_response_redacted json NOT NULL DEFAULT (JSON_OBJECT()), reconciliation_state varchar(32), reconciliation_attempt_count int NOT NULL DEFAULT 0,
  reconciliation_failure_count int NOT NULL DEFAULT 0, reconciliation_next_at datetime(6), reconciliation_last_attempt_at datetime(6),
  reconciliation_error_code varchar(191), reconciliation_alerted_at datetime(6),
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT, UNIQUE KEY uq_payments_order_method (order_id, method),
  INDEX payments_order_idx (order_id, created_at, id), INDEX payments_reconciliation_due_idx (method, reconciliation_state, reconciliation_next_at, id),
  CHECK (amount >= 0), CHECK (version >= 1)
) ENGINE=InnoDB;

CREATE TABLE payment_events (
  id char(36) PRIMARY KEY, payment_id char(36) NOT NULL, provider varchar(32) NOT NULL, provider_event_id varchar(191) NOT NULL,
  event_type varchar(191) NOT NULL, payload_redacted json NOT NULL DEFAULT (JSON_OBJECT()), received_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  processed_at datetime(6), FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE RESTRICT, UNIQUE KEY uq_payment_events_provider (provider, provider_event_id)
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  id char(36) PRIMARY KEY, aggregate_type varchar(64) NOT NULL, aggregate_id char(36) NOT NULL, action varchar(191) NOT NULL,
  actor_type varchar(16) NOT NULL, actor_id varchar(191), request_id varchar(128) NOT NULL, metadata_redacted json NOT NULL DEFAULT (JSON_OBJECT()),
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), INDEX audit_logs_aggregate_idx (aggregate_type, aggregate_id, created_at, id)
) ENGINE=InnoDB;

CREATE TABLE outbox_events (
  id char(36) PRIMARY KEY, aggregate_type varchar(64) NOT NULL, aggregate_id char(36) NOT NULL, event_type varchar(191) NOT NULL,
  payload json NOT NULL, deduplication_key varchar(191) NOT NULL UNIQUE, status varchar(32) NOT NULL DEFAULT 'PENDING', attempts int NOT NULL DEFAULT 0,
  available_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), published_at datetime(6), last_error_code varchar(191),
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  INDEX outbox_events_dispatch_idx (status, available_at, id)
) ENGINE=InnoDB;

CREATE TABLE whatsapp_inbound_messages (
  id char(36) PRIMARY KEY, provider_message_id varchar(191) NOT NULL UNIQUE, webhook_request_id varchar(191), device_id varchar(191) NOT NULL,
  session_id varchar(191), event_type varchar(191) NOT NULL, from_raw varchar(191) NOT NULL, phone_e164 varchar(16), sender_name varchar(120),
  message_body text, payload_redacted json NOT NULL DEFAULT (JSON_OBJECT()), status varchar(32) NOT NULL DEFAULT 'RECEIVED', quarantine_reason text,
  received_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), processed_at datetime(6), created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  INDEX whatsapp_inbound_messages_status_received_idx (status, received_at), INDEX whatsapp_inbound_messages_phone_idx (phone_e164)
) ENGINE=InnoDB;

CREATE TABLE agent_runs (
  id char(36) PRIMARY KEY, inbound_message_id char(36), session varchar(191) NOT NULL, customer_phone varchar(16), model varchar(191) NOT NULL,
  prompt_version varchar(64) NOT NULL, confidence_score decimal(3,2) NOT NULL, is_ambiguous boolean NOT NULL DEFAULT false,
  ambiguity_reasons json NOT NULL DEFAULT (JSON_ARRAY()), extracted_draft json NOT NULL DEFAULT (JSON_OBJECT()), tool_calls json NOT NULL DEFAULT (JSON_ARRAY()),
  duration_ms int NOT NULL DEFAULT 0, status varchar(32) NOT NULL, error_message text, correlation_id varchar(191) NOT NULL,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), FOREIGN KEY (inbound_message_id) REFERENCES whatsapp_inbound_messages(id) ON DELETE SET NULL,
  INDEX agent_runs_correlation_idx (correlation_id), INDEX agent_runs_status_created_idx (status, created_at), INDEX agent_runs_inbound_message_idx (inbound_message_id)
) ENGINE=InnoDB;

CREATE TABLE agent_conversations (
  id char(36) PRIMARY KEY, session varchar(191) NOT NULL, customer_phone varchar(16) NOT NULL, status varchar(32) NOT NULL DEFAULT 'COLLECTING',
  current_draft json NOT NULL DEFAULT (JSON_OBJECT()), pending_ambiguity text, clarification_attempts int NOT NULL DEFAULT 0, last_question text,
  last_inbound_message_id char(36), correlation_id varchar(191) NOT NULL, is_paused boolean NOT NULL DEFAULT false, paused_by varchar(191),
  paused_at datetime(6), paused_reason text, resumed_by varchar(191), resumed_at datetime(6), handoff_status varchar(32) NOT NULL DEFAULT 'NONE',
  handoff_reason text, handoff_priority varchar(16) NOT NULL DEFAULT 'NORMAL', assigned_to varchar(191), assigned_at datetime(6), resolved_at datetime(6),
  tool_failure_count int NOT NULL DEFAULT 0, confirmation_token varchar(191), draft_version int NOT NULL DEFAULT 1, last_order_id char(36),
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_agent_conversations_session_phone (session, customer_phone), INDEX agent_conversations_status_idx (status),
  INDEX idx_agent_conversations_handoff_queue (handoff_status, handoff_priority, updated_at), INDEX idx_agent_conversations_last_order (last_order_id),
  FOREIGN KEY (last_inbound_message_id) REFERENCES whatsapp_inbound_messages(id) ON DELETE SET NULL, FOREIGN KEY (last_order_id) REFERENCES orders(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE agent_conversation_audits (
  id char(36) PRIMARY KEY, conversation_id char(36) NOT NULL, session varchar(191) NOT NULL, customer_phone varchar(16) NOT NULL,
  action varchar(32) NOT NULL, actor varchar(191) NOT NULL, actor_role varchar(16) NOT NULL DEFAULT 'STAFF', reason text NOT NULL,
  metadata json NOT NULL DEFAULT (JSON_OBJECT()), correlation_id varchar(191) NOT NULL, created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (conversation_id) REFERENCES agent_conversations(id) ON DELETE CASCADE,
  INDEX idx_agent_conversation_audits_conv (conversation_id, created_at), INDEX idx_agent_conversation_audits_created (created_at)
) ENGINE=InnoDB;

CREATE TABLE customer_opt_outs (
  id char(36) PRIMARY KEY, phone_e164 varchar(16) NOT NULL UNIQUE, reason text, created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

CREATE TABLE order_notifications (
  id char(36) PRIMARY KEY, order_id char(36) NOT NULL, customer_phone varchar(16) NOT NULL, notification_type varchar(32) NOT NULL,
  template_version varchar(32) NOT NULL DEFAULT 'v1', idempotency_key varchar(191) NOT NULL UNIQUE, message_text text NOT NULL,
  status varchar(32) NOT NULL DEFAULT 'PENDING', suppress_reason varchar(64), provider_message_id varchar(191), attempts int NOT NULL DEFAULT 0,
  last_error text, sent_at datetime(6), next_retry_at datetime(6), max_attempts int NOT NULL DEFAULT 5, error_category varchar(64),
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE, INDEX idx_order_notifications_order_type (order_id, notification_type),
  INDEX idx_order_notifications_status (status, created_at), INDEX idx_order_notifications_outbox (status, next_retry_at, created_at)
) ENGINE=InnoDB;

CREATE TABLE app_users (
  id char(36) PRIMARY KEY, email_normalized varchar(320) NOT NULL UNIQUE, display_name varchar(160) NOT NULL DEFAULT '', role varchar(16) NOT NULL,
  status varchar(32) NOT NULL DEFAULT 'PENDING_APPROVAL', approved_by char(36), status_reason varchar(500), approved_at datetime(6),
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  FOREIGN KEY (approved_by) REFERENCES app_users(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE external_identities (
  id char(36) PRIMARY KEY, user_id char(36) NOT NULL, provider varchar(32) NOT NULL, provider_subject varchar(255) NOT NULL,
  email_at_login varchar(320) NOT NULL, created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), last_login_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE CASCADE, UNIQUE KEY uq_external_provider_subject (provider, provider_subject),
  UNIQUE KEY uq_external_provider_user (provider, user_id)
) ENGINE=InnoDB;

CREATE TABLE app_sessions (
  id varchar(128) PRIMARY KEY, user_id char(36) NOT NULL, expires_at datetime(6) NOT NULL, revoked_at datetime(6),
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE CASCADE,
  INDEX app_sessions_user_active_idx (user_id, expires_at)
) ENGINE=InnoDB;

CREATE TABLE user_status_audits (
  id char(36) PRIMARY KEY, user_id char(36) NOT NULL, actor_user_id char(36), from_status varchar(32), to_status varchar(32) NOT NULL,
  reason_redacted varchar(500), request_id varchar(128) NOT NULL, created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE RESTRICT, FOREIGN KEY (actor_user_id) REFERENCES app_users(id) ON DELETE RESTRICT,
  INDEX user_status_audits_user_idx (user_id, created_at, id)
) ENGINE=InnoDB;

CREATE TABLE user_invitations (
  id char(36) PRIMARY KEY, email_normalized varchar(320) NOT NULL UNIQUE, invited_by char(36) NOT NULL,
  outlet_name varchar(120) NOT NULL DEFAULT 'PesenHub Outlet #01', status varchar(32) NOT NULL DEFAULT 'PENDING', expires_at datetime(6) NOT NULL,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  FOREIGN KEY (invited_by) REFERENCES app_users(id) ON DELETE RESTRICT, INDEX user_invitations_status_idx (status, expires_at)
) ENGINE=InnoDB;

CREATE TABLE system_traffic_samples (
  bucket_time datetime(6) PRIMARY KEY, total_requests int NOT NULL DEFAULT 0, success_requests int NOT NULL DEFAULT 0,
  client_errors int NOT NULL DEFAULT 0, server_errors int NOT NULL DEFAULT 0, latency_p50_ms int NOT NULL DEFAULT 0,
  latency_p95_ms int NOT NULL DEFAULT 0, wa_inbound_count int NOT NULL DEFAULT 0, wa_outbound_count int NOT NULL DEFAULT 0,
  sync_success_count int NOT NULL DEFAULT 0, sync_failure_count int NOT NULL DEFAULT 0, sync_conflict_count int NOT NULL DEFAULT 0,
  INDEX system_traffic_samples_time_idx (bucket_time DESC)
) ENGINE=InnoDB;

INSERT INTO app_metadata (`key`, `value`) VALUES ('schema_foundation', 'mysql-baseline-v1');
