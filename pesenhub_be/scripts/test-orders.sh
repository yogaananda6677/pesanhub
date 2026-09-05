#!/usr/bin/env bash
set -Eeuo pipefail

container="pesenhub-order-test-$$"
password="order-test-only"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --rm --name "$container" -e POSTGRES_DB=pesenhub_test -e POSTGRES_USER=pesenhub_test -e POSTGRES_PASSWORD="$password" -p 127.0.0.1::5432 postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do docker exec "$container" pg_isready -h 127.0.0.1 -p 5432 -U pesenhub_test -d pesenhub_test >/dev/null 2>&1 && break; sleep 1; done
docker exec "$container" pg_isready -h 127.0.0.1 -p 5432 -U pesenhub_test -d pesenhub_test >/dev/null
sleep 1
port="$(docker port "$container" 5432/tcp | sed 's/.*://')"
export DATABASE_HOST=127.0.0.1 DATABASE_PORT="$port" DATABASE_NAME=pesenhub_test DATABASE_USER=pesenhub_test DATABASE_PASSWORD="$password" DATABASE_SSLMODE=disable GOWA_BASE_URL=http://127.0.0.1:3000 GOWA_BASIC_AUTH_USERNAME=test GOWA_BASIC_AUTH_PASSWORD=test-only GOWA_DEVICE_ID=pesenhub-dev GOWA_WEBHOOK_SECRET=test-hmac-key-at-least-32-chars-long MIDTRANS_SERVER_KEY=SB-Mid-server-test MIDTRANS_MERCHANT_ID=G123456789 MIDTRANS_BASE_URL=https://api.sandbox.midtrans.com APP_STAFF_TOKEN=staff-script-token-at-least-32-characters APP_KDS_TOKEN=kds-script-token-at-least-32-charactersxx GOCACHE=/tmp/pesenhub-order-test-cache
go run ./cmd/migrate up
TEST_DATABASE_URL="postgres://pesenhub_test:${password}@127.0.0.1:${port}/pesenhub_test?sslmode=disable" go test ./internal/order -run Integration -count=1
TEST_DATABASE_URL="postgres://pesenhub_test:${password}@127.0.0.1:${port}/pesenhub_test?sslmode=disable" go test ./internal/gowa -run Integration -count=1
TEST_DATABASE_URL="postgres://pesenhub_test:${password}@127.0.0.1:${port}/pesenhub_test?sslmode=disable" go test ./internal/hermes -run Integration -count=1
TEST_DATABASE_URL="postgres://pesenhub_test:${password}@127.0.0.1:${port}/pesenhub_test?sslmode=disable" go test ./internal/notification -run Integration -count=1
TEST_DATABASE_URL="postgres://pesenhub_test:${password}@127.0.0.1:${port}/pesenhub_test?sslmode=disable" go test ./internal/payment -run Integration -count=1
