# Backend Phase 0 Requirements

## Software dan image

- Docker Engine `29.6.1` dan Docker Compose `v5.2.0` tersedia saat validasi.
- Bash diperlukan untuk `run.sh`; Git diperlukan untuk workflow kontribusi.
- Go `1.26.0`, sesuai directive pada `go.mod`.
- Builder API: `golang:1.26.0-alpine`.
- Runtime API: `alpine:3.24.1`, hanya berisi CA certificates, timezone data, binary statis, migration SQL, dan asset web.
- PostgreSQL: `postgres:16-alpine`.
- WAHA Core: `devlikeapro/waha:latest-2026.8.1`.

Runtime API menggunakan user non-root `pesenhub` UID/GID 10001 dan tidak memuat Go toolchain atau source Go.

## Service dan port

| Service | Host | Container | Fungsi |
| --- | ---: | ---: | --- |
| `api` | 8080 | 8080 | REST API dan placeholder Web Customer |
| `postgres` | 5432 | 5432 | Database; host port dapat dioverride dengan `POSTGRES_HOST_PORT` |
| `waha` | 3000 | 3000 | WhatsApp HTTP API |

Di network Docker, API selalu menggunakan `DATABASE_HOST=postgres`, `DATABASE_PORT=5432`, dan `WAHA_BASE_URL=http://waha:3000`.

## Environment

Salin `.env.example` menjadi `.env`. Aplikasi menggunakan `APP_NAME`, `APP_ENV`, `APP_HOST`, `APP_PORT`, `APP_TIMEZONE`, `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_SSLMODE`, `WAHA_BASE_URL`, `WAHA_API_KEY`, `WAHA_SESSION`, `WAHA_REQUEST_TIMEOUT`, dan secret `WAHA_WEBHOOK_HMAC_KEY`.

Compose juga menggunakan `POSTGRES_HOST_PORT`, `WAHA_DASHBOARD_USERNAME`, dan `WAHA_DASHBOARD_PASSWORD`. `.env` diabaikan dan tidak dimasukkan ke build context. Jangan menyimpan credential asli di repository.

Untuk API yang dijalankan langsung dari host, ubah `DATABASE_HOST=localhost` dan `WAHA_BASE_URL=http://localhost:3000`.

## Build, stack, migration, dan test

```bash
./run.sh setup
./run.sh build
./run.sh dev
./run.sh migrate-up
./run.sh test
./run.sh check
```

Migration runner memakai konfigurasi network Docker dan hanya mengubah schema sesuai file migration. Rollback satu langkah memakai argumen `down`.

## Troubleshooting health

```bash
./run.sh status
./run.sh health
docker compose exec postgres pg_isready
docker compose logs --no-color api
docker compose logs --no-color postgres
docker compose logs --no-color waha
```

- API tidak mulai: pastikan PostgreSQL mencapai `healthy`; `api` menunggu kondisi tersebut.
- Readiness 503: PostgreSQL tidak dapat diping dari API.
- Readiness `degraded`: PostgreSQL aktif tetapi API/session WAHA belum siap. Periksa `waha_api`, `waha_session`, dan `waha_reason`; `absent`/`disconnected` berbeda dari API `down` atau `timeout`.
- Port host bentrok: ubah hanya host mapping, misalnya `POSTGRES_HOST_PORT=55432`; jangan mengubah `DATABASE_PORT=5432` untuk API dalam Docker.

Hentikan stack tanpa menghapus data dengan `docker compose down`.
