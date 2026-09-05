#!/usr/bin/env bash
set -Eeuo pipefail

container="pesenhub-migration-test-$$"
password="migration-test-only"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --rm --name "$container" -e POSTGRES_DB=pesenhub_test -e POSTGRES_USER=pesenhub_test -e POSTGRES_PASSWORD="$password" -p 127.0.0.1::5432 postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do
  docker exec "$container" pg_isready -h 127.0.0.1 -p 5432 -U pesenhub_test -d pesenhub_test >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$container" pg_isready -h 127.0.0.1 -p 5432 -U pesenhub_test -d pesenhub_test >/dev/null
sleep 1
port="$(docker port "$container" 5432/tcp | sed 's/.*://')"

run_migration() {
  DATABASE_HOST=127.0.0.1 DATABASE_PORT="$port" DATABASE_NAME=pesenhub_test DATABASE_USER=pesenhub_test DATABASE_PASSWORD="$password" DATABASE_SSLMODE=disable GOWA_BASE_URL=http://127.0.0.1:3000 GOWA_BASIC_AUTH_USERNAME=test GOWA_BASIC_AUTH_PASSWORD=test-only GOWA_DEVICE_ID=pesenhub-dev GOWA_WEBHOOK_SECRET=test-hmac-key-at-least-32-chars-long MIDTRANS_SERVER_KEY=SB-Mid-server-test MIDTRANS_MERCHANT_ID=G123456789 MIDTRANS_BASE_URL=https://api.sandbox.midtrans.com APP_STAFF_TOKEN=staff-script-token-at-least-32-characters APP_KDS_TOKEN=kds-script-token-at-least-32-charactersxx GOCACHE=/tmp/pesenhub-migration-test-cache go run ./cmd/migrate "$1"
}

run_migration up
docker exec -i "$container" psql -v ON_ERROR_STOP=1 -U pesenhub_test -d pesenhub_test <<'SQL'
INSERT INTO customers (id, phone_e164, display_name, preferences, create_idempotency_key) VALUES ('01000000-0000-0000-0000-000000000001', '+6281234567890', 'Test Customer', '{"spicy":true}', 'customer-test-1');
INSERT INTO menu_categories (id, name) VALUES ('10000000-0000-0000-0000-000000000001', 'Makanan');
INSERT INTO menus (id, category_id, sku, name, price_amount) VALUES ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'NASGOR', 'Nasi Goreng', 15000);
INSERT INTO orders (id, order_number, source, customer_name_snapshot, subtotal_amount, total_amount, idempotency_key) VALUES ('30000000-0000-0000-0000-000000000001', 'ORD-TEST-1', 'CASHIER_MANUAL', 'Test Customer', 15000, 15000, 'order-test-1');
INSERT INTO orders (id, order_number, source, customer_name_snapshot, subtotal_amount, total_amount, idempotency_key) VALUES ('30000000-0000-0000-0000-000000000003', 'ORD-TEST-3', 'CASHIER_MANUAL', 'Second Test Customer', 0, 0, 'order-test-3');
INSERT INTO order_items (id, order_id, menu_id, menu_name_snapshot, sku_snapshot, unit_price_amount, quantity, line_total_amount) VALUES ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Nasi Goreng', 'NASGOR', 15000, 1, 15000);
INSERT INTO order_status_history (id, order_id, to_status, order_version, actor_type, request_id) VALUES ('50000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'PENDING', 1, 'STAFF', 'migration-test');
INSERT INTO payments (id, order_id, method, status, amount, idempotency_key) VALUES ('60000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'CASH', 'UNPAID', 15000, 'payment-test-1');
INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, payload, deduplication_key) VALUES ('70000000-0000-0000-0000-000000000001', 'ORDER', '30000000-0000-0000-0000-000000000001', 'ORDER_CREATED', '{}', 'outbox-test-1');
INSERT INTO whatsapp_inbound_messages (id, provider_message_id, device_id, session_id, event_type, from_raw, phone_e164, status) VALUES ('75000000-0000-0000-0000-000000000001', 'wamid-test-1', 'pesenhub-dev', 'default', 'message', '628123456789@s.whatsapp.net', '+628123456789', 'RECEIVED');
INSERT INTO agent_runs (id, inbound_message_id, session, customer_phone, model, prompt_version, confidence_score, status, correlation_id) VALUES ('76000000-0000-0000-0000-000000000001', '75000000-0000-0000-0000-000000000001', 'default', '+628123456789', 'hermes-3-llama-3.1-8b', 'v1.0.0', 0.95, 'SUCCESS', 'corr-migration-test');
INSERT INTO agent_conversations (id, session, customer_phone, status, correlation_id) VALUES ('77000000-0000-0000-0000-000000000001', 'default', '+628123456789', 'COLLECTING', 'corr-conv-test');
INSERT INTO order_notifications (id, order_id, customer_phone, notification_type, idempotency_key, message_text, status, error_category) VALUES ('78000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '+628123456789', 'CONFIRMATION', 'notification-test-1', 'Test notification', 'FAILED', 'DEVICE_NOT_READY');
DO $$ BEGIN
  BEGIN
    INSERT INTO orders (id, order_number, source, customer_name_snapshot, subtotal_amount, total_amount, idempotency_key) VALUES ('30000000-0000-0000-0000-000000000002', 'ORD-TEST-2', 'CASHIER_MANUAL', 'Test Customer', 0, 0, 'order-test-1');
    RAISE EXCEPTION 'duplicate idempotency key unexpectedly accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    UPDATE orders SET status = 'READY' WHERE id = '30000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'invalid status unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
SQL

run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='payments' AND column_name='reconciliation_state'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.payments_reconciliation_due_idx') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='payments' AND column_name='provider_order_id'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.payments_one_midtrans_qris_per_order_idx') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.whatsapp_inbound_messages') IS NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*) FROM waha_inbound_messages WHERE provider_message_id='wamid-test-1' AND session='pesenhub-dev'")" = "1"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*) FROM order_notifications WHERE id='78000000-0000-0000-0000-000000000001' AND error_category='SESSION_NOT_READY'")" = "1"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='payments' AND column_name='request_hash'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.payments_one_cash_per_order_idx') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='order_notifications' AND column_name='next_retry_at'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='order_notifications' AND column_name='error_category'")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.order_notifications') IS NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.customer_opt_outs') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='agent_conversations' AND column_name='confirmation_token'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='agent_conversations' AND column_name='draft_version'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='agent_conversations' AND column_name='last_order_id'")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversation_audits') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversations') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_runs') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.waha_inbound_messages') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='orders' AND column_name='public_tracking_token'")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.orders_source_status_created_idx') IS NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='order_status_history' AND column_name='request_hash'")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='orders' AND column_name='client_order_id'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.modifier_groups') IS NOT NULL")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.modifier_groups') IS NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='customers' AND column_name='preferences'")" = "t"
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=0 FROM information_schema.columns WHERE table_name='customers' AND column_name='preferences'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.orders') IS NOT NULL")" = "t"
run_migration up
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='customers' AND column_name='preferences'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.modifier_groups') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.whatsapp_inbound_messages') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_runs') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversations') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversation_audits') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='agent_conversations' AND column_name='confirmation_token'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.order_notifications') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.customer_opt_outs') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='payments' AND column_name='request_hash'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='payments' AND column_name='provider_order_id'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='payments' AND column_name='reconciliation_failure_count'")" = "t"
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.orders') IS NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.app_metadata') IS NOT NULL")" = "t"
run_migration up
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.outbox_events') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='customers' AND column_name='preferences'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.whatsapp_inbound_messages') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_runs') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversations') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversation_audits') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='agent_conversations' AND column_name='confirmation_token'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.order_notifications') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.customer_opt_outs') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='order_notifications' AND column_name='next_retry_at'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.payments_reconciliation_due_idx') IS NOT NULL")" = "t"

docker exec "$container" psql -v ON_ERROR_STOP=1 -U pesenhub_test -d pesenhub_test -c "INSERT INTO customers (id, phone_e164, display_name, create_idempotency_key) VALUES ('81000000-0000-0000-0000-000000000001', '+628111111111', 'Race Test', 'race-key-1') ON CONFLICT DO NOTHING" >/dev/null &
first_pid=$!
docker exec "$container" psql -v ON_ERROR_STOP=1 -U pesenhub_test -d pesenhub_test -c "INSERT INTO customers (id, phone_e164, display_name, create_idempotency_key) VALUES ('81000000-0000-0000-0000-000000000002', '+628111111111', 'Race Test', 'race-key-2') ON CONFLICT DO NOTHING" >/dev/null &
second_pid=$!
wait "$first_pid" "$second_pid"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*) FROM customers WHERE phone_e164='+628111111111'")" = "1"

docker exec -i "$container" psql -v ON_ERROR_STOP=1 -U pesenhub_test -d pesenhub_test <<'SQL'
INSERT INTO menu_categories(id,name,sort_order) VALUES ('91000000-0000-0000-0000-000000000001','Minuman',2),('91000000-0000-0000-0000-000000000002','Makanan',1);
INSERT INTO menus(id,category_id,sku,name,price_amount,is_available,sort_order) VALUES
('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000002','NASGOR','Nasi Goreng',15000,true,2),
('92000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002','MIE','Mie Goreng',14000,false,1);
INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,sort_order) VALUES ('93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','spice','Level Pedas',1,1,1);
INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,sort_order) VALUES ('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','hot','Pedas',0,1);
DO $$ BEGIN
  BEGIN
    INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select) VALUES ('93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001','invalid','Invalid',2,1);
    RAISE EXCEPTION 'invalid modifier bounds unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
SQL
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT string_agg(name,',' ORDER BY sort_order,name,id) FROM menus WHERE is_available")" = "Nasi Goreng"
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
run_migration down
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.modifier_groups') IS NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.customers') IS NOT NULL")" = "t"
run_migration up
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.modifier_options') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.whatsapp_inbound_messages') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_runs') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversations') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.agent_conversation_audits') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='agent_conversations' AND column_name='confirmation_token'")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.order_notifications') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT to_regclass('public.customer_opt_outs') IS NOT NULL")" = "t"
test "$(docker exec "$container" psql -At -U pesenhub_test -d pesenhub_test -c "SELECT count(*)=1 FROM information_schema.columns WHERE table_name='order_notifications' AND column_name='next_retry_at'")" = "t"
echo "Migration up/down/up, customer collision, and catalog constraint/visibility checks passed."
