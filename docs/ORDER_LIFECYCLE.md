# Order Lifecycle

Order final memakai state machine berikut:

```text
PENDING -> ACCEPTED -> PREPARING -> READY_FOR_PICKUP -> COMPLETED
PENDING -> REJECTED
PENDING | ACCEPTED -> CANCELLED
```

`COMPLETED`, `REJECTED`, dan `CANCELLED` bersifat terminal. Pembatalan setelah `PREPARING` tidak diizinkan tanpa policy baru yang disetujui.

Staff mengirim `POST /api/v1/orders/{id}/status-transitions` dengan `target_status`, `expected_version`, dan header `Idempotency-Key`. Transisi sah menaikkan version satu kali serta menyimpan history, audit log, dan outbox event dalam transaksi yang sama. Stale version dan transisi ilegal menghasilkan `409` tanpa mutasi.

Setiap history transisi menyimpan hash payload dan idempotency key. Replay identik mengembalikan status/version hasil pertama tanpa history, audit, atau event tambahan; penggunaan key yang sama dengan payload berbeda menghasilkan `IDEMPOTENCY_CONFLICT`.

Endpoint hanya menerima principal `STAFF` dan tetap default-deny sampai middleware autentikasi produksi tersedia.
