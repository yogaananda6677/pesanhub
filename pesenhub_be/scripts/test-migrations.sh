#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
container="pesenhub-mysql-migration-test-$$"
password="migration_test_only_password"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --rm --name "$container" \
  -e MYSQL_DATABASE=pesenhub_test \
  -e MYSQL_USER=pesenhub_test \
  -e MYSQL_PASSWORD="$password" \
  -e MYSQL_ROOT_PASSWORD=root_test_only_password \
  -p 127.0.0.1::3306 mysql:8.4 >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$container" mysqladmin ping -h 127.0.0.1 -upesenhub_test -p"$password" --silent >/dev/null 2>&1; then break; fi
  sleep 1
done
docker exec "$container" mysqladmin ping -h 127.0.0.1 -upesenhub_test -p"$password" --silent >/dev/null

port="$(docker port "$container" 3306/tcp | sed 's/.*://')"
export APP_ENV=test DATABASE_HOST=127.0.0.1 DATABASE_PORT="$port" DATABASE_NAME=pesenhub_test DATABASE_USER=pesenhub_test DATABASE_PASSWORD="$password" DATABASE_TLS=false
export GOWA_BASE_URL=http://localhost:3000 GOWA_BASIC_AUTH_USERNAME=test GOWA_BASIC_AUTH_PASSWORD=test GOWA_DEVICE_ID=test GOWA_WEBHOOK_SECRET=12345678901234567890123456789012
export MIDTRANS_SERVER_KEY=test MIDTRANS_MERCHANT_ID=test APP_STAFF_TOKEN=12345678901234567890123456789012 APP_KDS_TOKEN=abcdefghijklmnopqrstuvwxyz123456 APP_SESSION_SECRET=abcdefghijklmnopqrstuvwxyz123456 GOOGLE_OAUTH_CLIENT_ID=test.apps.googleusercontent.com

cd "$repo_dir"
go run ./cmd/migrate up
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='pesenhub_test' AND table_name IN ('orders','payments','whatsapp_inbound_messages','app_users','system_traffic_samples');" 2>/dev/null)" = "5"
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT dirty FROM schema_migrations WHERE version=5;" 2>/dev/null)" = "0"
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='pesenhub_test' AND table_name='user_invitations' AND column_name IN ('role','accepted_user_id','accepted_at');" 2>/dev/null)" = "3"
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='pesenhub_test' AND table_name='menus' AND column_name='hpp_amount';" 2>/dev/null)" = "1"
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='pesenhub_test' AND table_name='menus' AND column_name IN ('product_type','image_url');" 2>/dev/null)" = "2"
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM menus WHERE id LIKE '20000000-0000-4000-8000-0000000000%';" 2>/dev/null)" = "13"
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM menu_channel_prices WHERE channel='OFFLINE' AND menu_id LIKE '20000000-0000-4000-8000-0000000000%';" 2>/dev/null)" = "13"
export TEST_DATABASE_URL="mysql://pesenhub_test:${password}@tcp(127.0.0.1:${port})/pesenhub_test?parseTime=true&loc=UTC&multiStatements=true&tls=false&charset=utf8mb4&collation=utf8mb4_0900_ai_ci"
go test ./internal/appauth -run Integration -count=1

go run ./cmd/migrate down
go run ./cmd/migrate down
go run ./cmd/migrate down
go run ./cmd/migrate down
go run ./cmd/migrate down
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='pesenhub_test' AND table_name='orders';" 2>/dev/null)" = "0"
go run ./cmd/migrate up
test "$(docker exec "$container" mysql -N -upesenhub_test -p"$password" pesenhub_test -e "SELECT COUNT(*) FROM app_metadata WHERE \`key\`='schema_foundation' AND \`value\`='mysql-admin-cashier-auth-v2';" 2>/dev/null)" = "1"

echo "MySQL migration up/down/up contract passed."
