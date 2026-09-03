# Manual Cashier Order Creation

`POST /api/v1/orders` membuat order `CASHIER_MANUAL` berstatus `PENDING`. Endpoint ini khusus principal `STAFF`; wiring autentikasi principal dikerjakan oleh issue autentikasi terpisah sehingga server tetap default-deny tanpa middleware tersebut.

Klien wajib mengirim UUID `client_order_id` dan header `Idempotency-Key`. Backend menormalisasi input, menghitung SHA-256 payload, lalu mengambil PostgreSQL advisory transaction lock untuk pasangan source/key. Replay dengan payload sama mengembalikan order yang sama (`200`), sedangkan payload berbeda ditolak dengan `409 IDEMPOTENCY_CONFLICT`.

Harga, ketersediaan, aturan min/max modifier, nama, SKU, dan delta modifier dibaca ulang dari database di dalam transaksi. Backend mengabaikan total dari klien dan menyimpan snapshot order item. Insert order, item, modifier, status history awal, audit log, dan outbox event dilakukan atomik; kegagalan validasi tidak meninggalkan data parsial.

Validasi lokal:

```bash
cd pesenhub_be
./run.sh check
./scripts/test-migrations.sh
./scripts/test-orders.sh
GOCACHE=/tmp/pesenhub-race-cache go test -race ./...
```
