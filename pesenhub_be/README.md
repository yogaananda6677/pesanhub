# PesenHub Backend

Kontrak HTTP lintas endpoint mengikuti [`docs/API_CONVENTIONS.md`](../docs/API_CONVENTIONS.md) dan schema OpenAPI [`docs/api/openapi.yaml`](../docs/api/openapi.yaml).
Model data inti dan ERD tersedia di [`docs/CORE_DOMAIN_MODEL.md`](../docs/CORE_DOMAIN_MODEL.md). Jalankan integration test migration terisolasi dengan `./scripts/test-migrations.sh`.

Fondasi REST API Phase 0. Cara utama menjalankan PesenHub adalah Docker Compose: API Golang, PostgreSQL, dan WAHA berada dalam satu network. Web Customer masih berupa placeholder dan tidak ada pairing atau pengiriman WhatsApp otomatis.

## Quick start

```bash
cd pesenhub_be
./run.sh setup
./run.sh dev
./run.sh status
./run.sh health
```

Panduan lengkap dan aturan operasional tersedia di [ATURAN.md](ATURAN.md).

Readiness gagal dengan HTTP 503 bila PostgreSQL turun. WAHA yang belum memiliki session menghasilkan HTTP 200 berstatus `degraded`, sehingga API tetap dapat diperiksa tanpa pairing.

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
./run.sh logs waha
./run.sh down
```

`docker compose down` mempertahankan named volume. Jangan menggunakan `docker compose down -v` kecuali penghapusan data memang dimaksudkan.

Jalankan `./run.sh help` untuk seluruh command. Target Makefile adalah wrapper tipis bagi script tersebut agar logika operasional tidak terduplikasi.

## Menjalankan Go langsung

Untuk development tanpa container API, PostgreSQL dan WAHA tetap dapat dijalankan melalui Compose. Ubah `.env` menjadi `DATABASE_HOST=localhost` dan `WAHA_BASE_URL=http://localhost:3000`, muat variabel ke shell, lalu jalankan:

```bash
set -a; . ./.env; set +a
go run ./cmd/api
```

Detail versi, port, konfigurasi, dan troubleshooting ada di [REQUIREMENTS.md](REQUIREMENTS.md).
