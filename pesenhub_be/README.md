# PesenHub Backend

Kontrak HTTP lintas endpoint mengikuti [`docs/API_CONVENTIONS.md`](../docs/API_CONVENTIONS.md) dan schema OpenAPI [`docs/api/openapi.yaml`](../docs/api/openapi.yaml).
Model data inti dan ERD tersedia di [`docs/CORE_DOMAIN_MODEL.md`](../docs/CORE_DOMAIN_MODEL.md). Jalankan integration test migration terisolasi dengan `./scripts/test-migrations.sh`.

Fondasi REST API Phase 0. Cara utama menjalankan PesenHub adalah Docker Compose: API Golang, PostgreSQL, dan GOWA berada dalam satu network. Web Customer masih berupa placeholder dan tidak ada pairing atau pengiriman WhatsApp otomatis.

## Quick start

```bash
cd pesenhub_be
./run.sh setup
./run.sh dev
./run.sh status
./run.sh health
```

Panduan lengkap dan aturan operasional tersedia di [ATURAN.md](ATURAN.md).

Readiness gagal dengan HTTP 503 bila PostgreSQL turun. GOWA yang belum memiliki device terhubung menghasilkan HTTP 200 berstatus `degraded`; field `gowa_api`, `gowa_device`, dan `gowa_reason` membedakan API gagal, device tidak ada, device terputus, dan timeout tanpa melakukan pairing otomatis.

Webhook GOWA diterima pada `POST /webhooks/gowa` dan wajib memakai header HMAC-SHA256 `X-Hub-Signature-256`. Lihat [GOWA_HEALTH_WEBHOOK_SECURITY.md](../docs/GOWA_HEALTH_WEBHOOK_SECURITY.md) sebelum memasangkan device development.

## Midtrans sandbox QRIS

Isi `MIDTRANS_SERVER_KEY` dan `MIDTRANS_MERCHANT_ID` dengan credential **sandbox** lokal (jangan commit nilainya). Endpoint operator `POST /api/v1/orders/{id}/payments/qris` wajib memakai autentikasi staf dan `Idempotency-Key`; body tidak menerima nominal karena `gross_amount` selalu dibaca dari total order backend. Respons sukses berisi URL QR dan status `PENDING_PAYMENT`. Timeout/network/5xx menghasilkan `503 PAYMENT_PROVIDER_UNAVAILABLE` dan harus diulang dengan key yang sama; 4xx provider menghasilkan `422 PAYMENT_PROVIDER_REJECTED`.

Konfigurasi `MIDTRANS_BASE_URL` dibatasi ke `https://api.sandbox.midtrans.com` di luar test, dengan timeout melalui `MIDTRANS_REQUEST_TIMEOUT`. Server key tidak disimpan pada payment event, audit, outbox, database response allowlist, atau respons HTTP.

Atur Payment Notification URL sandbox ke `POST /webhooks/midtrans`. Endpoint publik ini tidak memakai bearer token karena Midtrans tidak mendukung custom authorization header; setiap payload diverifikasi memakai signature SHA-512, merchant ID, channel QRIS, mata uang IDR, provider order ID, transaction ID, dan nominal backend. Duplicate direspons `200` dengan `X-PesenHub-Deduplicated: true`. Notifikasi terlambat tidak dapat menurunkan `PAID`/`REFUNDED`, dan perubahan payment tidak pernah otomatis menyelesaikan order.

Rekonsiliasi status berjalan otomatis untuk charge dengan hasil tidak diketahui dan QRIS non-terminal yang sudah waktunya diperiksa. Worker memanggil Get Status API memakai provider order ID stabil, memvalidasi kembali identitas transaksi, nominal, channel, mata uang, dan status, lalu menerapkan state machine yang sama dengan webhook. Jam lokal atau `expires_at` saja tidak pernah menandai payment `EXPIRED`; bukti status `expire` dari Midtrans wajib ada. Kegagalan memakai backoff eksponensial, berhenti setelah lima percobaan, dan menghasilkan audit serta outbox alert tanpa raw response atau credential.

Staf dapat memicu satu pemeriksaan melalui `POST /api/v1/payments/{id}/reconcile`. Respons `200` berarti status provider tervalidasi; `202` berarti retry/alert sudah dicatat. Webhook tetap source of truth utama dan rekonsiliasi hanya memperbaiki event yang hilang atau hasil request yang tidak diketahui. Detail state dan runbook ada di [MIDTRANS_RECONCILIATION.md](../docs/MIDTRANS_RECONCILIATION.md).

## Migration

Setelah stack menyala:

```bash
./run.sh migrate-up
./run.sh migrate-status
./run.sh migrate-down
```

`down` hanya melakukan rollback satu migration. Migration tidak dijalankan otomatis saat startup dan tidak menghapus volume.

## Operasional

```bash
./run.sh logs api
./run.sh logs postgres
./run.sh logs gowa
./run.sh down
```

`docker compose down` mempertahankan named volume. Jangan menggunakan `docker compose down -v` kecuali penghapusan data memang dimaksudkan.

Jalankan `./run.sh help` untuk seluruh command. Target Makefile adalah wrapper tipis bagi script tersebut agar logika operasional tidak terduplikasi.

## Menjalankan Go langsung

Untuk development tanpa container API, PostgreSQL dan GOWA tetap dapat dijalankan melalui Compose. Ubah `.env` menjadi `DATABASE_HOST=localhost` dan `GOWA_BASE_URL=http://localhost:3000`, muat variabel ke shell, lalu jalankan:

```bash
set -a; . ./.env; set +a
go run ./cmd/api
```

Detail versi, port, konfigurasi, dan troubleshooting ada di [REQUIREMENTS.md](REQUIREMENTS.md).
