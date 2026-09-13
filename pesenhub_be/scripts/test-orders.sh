#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
container="pesenhub-integration-test-$$"
password="integration-test-only"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --rm --name "$container" \
  -e MYSQL_DATABASE=pesenhub_test -e MYSQL_USER=pesenhub_test \
  -e MYSQL_PASSWORD="$password" -e MYSQL_ROOT_PASSWORD=root-test-only \
  -p 127.0.0.1::3306 mysql:8.4 >/dev/null
for _ in $(seq 1 60); do
  docker exec "$container" mysqladmin ping -h127.0.0.1 -upesenhub_test -p"$password" --silent >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$container" mysqladmin ping -h127.0.0.1 -upesenhub_test -p"$password" --silent >/dev/null
port="$(docker port "$container" 3306/tcp | sed 's/.*://')"

export APP_ENV=test DATABASE_HOST=127.0.0.1 DATABASE_PORT="$port" DATABASE_NAME=pesenhub_test DATABASE_USER=pesenhub_test DATABASE_PASSWORD="$password" DATABASE_TLS=false
export GOWA_BASE_URL=http://127.0.0.1:3000 GOWA_BASIC_AUTH_USERNAME=test GOWA_BASIC_AUTH_PASSWORD=test-only GOWA_DEVICE_ID=pesenhub-dev GOWA_WEBHOOK_SECRET=test-hmac-key-at-least-32-chars-long
export MIDTRANS_SERVER_KEY=SB-Mid-server-test MIDTRANS_MERCHANT_ID=G123456789 MIDTRANS_BASE_URL=https://api.sandbox.midtrans.com APP_STAFF_TOKEN=staff-script-token-at-least-32-characters APP_KDS_TOKEN=kds-script-token-at-least-32-charactersxx APP_SESSION_SECRET=session-script-secret-at-least-32-characters APP_SESSION_TTL=8h GOOGLE_OAUTH_CLIENT_ID=test.apps.googleusercontent.com
export TEST_DATABASE_URL="mysql://pesenhub_test:${password}@tcp(127.0.0.1:${port})/pesenhub_test?parseTime=true&loc=UTC&multiStatements=true&tls=false&charset=utf8mb4&collation=utf8mb4_0900_ai_ci"
export GOCACHE=/tmp/pesenhub-integration-test-cache

cd "$repo_dir"
go run ./cmd/migrate up
go test ./internal/... -count=1
