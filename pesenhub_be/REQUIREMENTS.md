# Backend Phase 0 Requirements

## Software dan image

- Docker Engine `29.6.1` dan Docker Compose `v5.2.0` tersedia saat validasi.
- Bash diperlukan untuk `run.sh`; Git diperlukan untuk workflow kontribusi.
- Go `1.26.0`, sesuai directive pada `go.mod`.
- Builder API: `golang:1.26.0-alpine`.
- Runtime API: `alpine:3.24.1`, hanya berisi CA certificates, timezone data, binary statis, migration SQL, dan asset web.
- PostgreSQL: `postgres:16-alpine`.
- GOWA: `aldinokemal2104/go-whatsapp-web-multidevice:v9.3.0`.

Runtime API menggunakan user non-root `pesenhub` UID/GID 10001 dan tidak memuat Go toolchain atau source Go.

## Service dan port

| Service | Host | Container | Fungsi |
| --- | ---: | ---: | --- |
| `api` | 8080 | 8080 | REST API dan placeholder Web Customer |
| `postgres` | 5432 | 5432 | Database; host port dapat dioverride dengan `POSTGRES_HOST_PORT` |
| `gowa` | 3000 | 3000 | WhatsApp HTTP API |

Di network Docker, API selalu menggunakan `DATABASE_HOST=postgres`, `DATABASE_PORT=5432`, dan `GOWA_BASE_URL=http://gowa:3000`.

## Environment

Salin `.env.example` menjadi `.env`. Aplikasi menggunakan `APP_NAME`, `APP_ENV`, `APP_HOST`, `APP_PORT`, `APP_TIMEZONE`, konfigurasi PostgreSQL, `GOWA_BASE_URL`, `GOWA_BASIC_AUTH_USERNAME`, `GOWA_BASIC_AUTH_PASSWORD`, `GOWA_DEVICE_ID`, `GOWA_REQUEST_TIMEOUT`, `GOWA_WEBHOOK_SECRET`, serta konfigurasi sandbox `MIDTRANS_BASE_URL`, `MIDTRANS_SERVER_KEY`, dan `MIDTRANS_REQUEST_TIMEOUT`.

Compose juga menggunakan `POSTGRES_HOST_PORT`; autentikasi API dan UI GOWA memakai pasangan Basic Auth yang sama. `.env` diabaikan dan tidak dimasukkan ke build context. Jangan menyimpan credential asli di repository.

Untuk API yang dijalankan langsung dari host, ubah `DATABASE_HOST=localhost` dan `GOWA_BASE_URL=http://localhost:3000`.

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
docker compose logs --no-color gowa
```

- API tidak mulai: pastikan PostgreSQL mencapai `healthy`; `api` menunggu kondisi tersebut.
- Readiness 503: PostgreSQL tidak dapat diping dari API.
- Readiness `degraded`: PostgreSQL aktif tetapi API/device GOWA belum siap. Periksa `gowa_api`, `gowa_device`, dan `gowa_reason`; `absent`/`disconnected` berbeda dari API `down` atau `timeout`.
- Port host bentrok: ubah hanya host mapping, misalnya `POSTGRES_HOST_PORT=55432`; jangan mengubah `DATABASE_PORT=5432` untuk API dalam Docker.

Hentikan stack tanpa menghapus data dengan `docker compose down`.
