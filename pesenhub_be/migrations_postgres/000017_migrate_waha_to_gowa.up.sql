ALTER TABLE waha_inbound_messages RENAME TO whatsapp_inbound_messages;
ALTER TABLE whatsapp_inbound_messages RENAME COLUMN session TO device_id;
ALTER TABLE whatsapp_inbound_messages ADD COLUMN session_id text;

ALTER INDEX waha_inbound_messages_status_received_idx RENAME TO whatsapp_inbound_messages_status_received_idx;
ALTER INDEX waha_inbound_messages_phone_idx RENAME TO whatsapp_inbound_messages_phone_idx;

COMMENT ON TABLE whatsapp_inbound_messages IS 'Provider-neutral WhatsApp inbound messages; migrated from WAHA to GOWA by issue 118.';

ALTER TABLE order_notifications DROP CONSTRAINT IF EXISTS order_notifications_error_category_check;

UPDATE order_notifications
SET error_category = 'DEVICE_NOT_READY'
WHERE error_category = 'SESSION_NOT_READY';

ALTER TABLE order_notifications ADD CONSTRAINT order_notifications_error_category_check
    CHECK (error_category IS NULL OR error_category IN (
        'TRANSIENT_TIMEOUT',
        'TRANSIENT_NETWORK',
        'TRANSIENT_PROVIDER',
        'DEVICE_NOT_READY',
        'PERMANENT_VALIDATION',
        'PERMANENT_AUTH',
        'MAX_ATTEMPTS_EXCEEDED',
        'UNKNOWN'
    ));
