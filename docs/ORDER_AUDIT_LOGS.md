# Order Mutation Audit Logging Specification

PesenHub mencatat setiap mutasi status dan pembuatan pesanan (`ORDER_CREATED`, `ORDER_STATUS_CHANGED`) secara *append-only* dan *immutable* ke dalam tabel `audit_logs`.

---

## 1. Prinsip & Kebijakan Audit

1. **Transactional Atomicity**: Pencatatan audit dijalankan di dalam transaksi database yang sama dengan mutasi status order. Jika transaksi gagal atau terjadi rollback (misal version conflict atau validation failure), tidak ada record audit palsu (*phantom audit*) yang tersimpan.
2. **Strict PII Redaction & Sanitization**:
   - Nomor handphone pelanggan **tidak pernah** disimpan dalam bentuk utuh di kolom `metadata_redacted`. Sistem secara otomatis menyamarkan nomor HP menggunakan fungsi `MaskPhone` (contoh: `+6281234567890` -> `+62812****7890`).
   - Kredensial rahasia, token akses, password, dan public tracking token disensor menjadi `[REDACTED]`.
3. **Actor Identification**: Setiap record audit mencatat identitas pemanggil:
   - `actor_type`: `STAFF`, `CUSTOMER`, `SYSTEM`, atau `AGENT`.
   - `actor_id`: UUID staf / pelanggan / nama sistem.
   - `request_id`: Correlation ID HTTP untuk keperluan pelacakan dan observabilitas end-to-end.
4. **Authorized Query with Self-Auditing**:
   - Endpoint query riwayat audit `GET /api/v1/orders/{id}/audit-logs` dilindungi otorisasi berbasis peran (RBAC) dan hanya dapat diakses oleh pengguna dengan role `STAFF`.
   - Setiap pemanggilan query audit dicatat kembali ke dalam tabel audit sebagai aksi `AUDIT_LOGS_ACCESSED` dengan `actor_id` staf dan `request_id` pemanggil.

---

## 2. Struktur Data Model (`audit_logs`)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid PRIMARY KEY` | UUID entri audit log |
| `aggregate_type` | `text NOT NULL` | Selalu `'ORDER'` untuk mutasi pesanan |
| `aggregate_id` | `uuid NOT NULL` | ID unik pesanan (`orders.id`) |
| `action` | `text NOT NULL` | `'ORDER_CREATED'`, `'ORDER_STATUS_CHANGED'`, `'AUDIT_LOGS_ACCESSED'` |
| `actor_type` | `text NOT NULL` | Enum: `'STAFF'`, `'CUSTOMER'`, `'SYSTEM'`, `'AGENT'` |
| `actor_id` | `text` | ID aktor yang melakukan aksi |
| `request_id` | `text NOT NULL` | HTTP correlation request ID |
| `metadata_redacted` | `jsonb NOT NULL` | Detail perubahan status & harga dengan PII tersensor |
| `created_at` | `timestamptz NOT NULL` | Waktu mutasi dicatat (UTC) |

---

## 3. Contoh Metadata Aman (Before-After & Redacted)

### A. Order Created (`ORDER_CREATED`)
```json
{
  "order_id": "d3000000-0000-4000-8000-000000000001",
  "order_number": "ORD-05F2157B9EAB4E21",
  "source": "CASHIER_MANUAL",
  "status": "PENDING",
  "customer_name": "Audit Tester",
  "customer_phone": "+62812****7890",
  "total_amount": 25000,
  "version": 1
}
```

### B. Order Status Changed (`ORDER_STATUS_CHANGED`)
```json
{
  "order_id": "d3000000-0000-4000-8000-000000000001",
  "from_status": "PENDING",
  "to_status": "ACCEPTED",
  "version": 2,
  "reason_code": "CUSTOMER_CONFIRMED"
}
```

### C. Audit Query Accessed (`AUDIT_LOGS_ACCESSED`)
```json
{}
```

---

## 4. Spesifikasi Kontrak API Query Audit

### `GET /api/v1/orders/{id}/audit-logs`

- **Otorisasi**: Memerlukan header autentikasi staf (`Authorization: Bearer <staff-token>`).
- **Path Parameter**:
  - `id`: UUID dari order yang dicari.
- **Respon Sukses `200 OK`**:
  ```json
  {
    "data": [
      {
        "id": "e1000000-0000-4000-8000-000000000001",
        "aggregate_type": "ORDER",
        "aggregate_id": "d3000000-0000-4000-8000-000000000001",
        "action": "ORDER_CREATED",
        "actor_type": "STAFF",
        "actor_id": "staff-uuid-1",
        "request_id": "req-xyz-1",
        "metadata": {
          "order_id": "d3000000-0000-4000-8000-000000000001",
          "order_number": "ORD-05F2157B9EAB4E21",
          "source": "CASHIER_MANUAL",
          "status": "PENDING",
          "customer_phone": "+62812****7890",
          "total_amount": 25000,
          "version": 1
        },
        "created_at": "2026-09-03T15:00:00Z"
      },
      {
        "id": "e2000000-0000-4000-8000-000000000001",
        "aggregate_type": "ORDER",
        "aggregate_id": "d3000000-0000-4000-8000-000000000001",
        "action": "ORDER_STATUS_CHANGED",
        "actor_type": "STAFF",
        "actor_id": "staff-uuid-1",
        "request_id": "req-xyz-2",
        "metadata": {
          "from_status": "PENDING",
          "to_status": "ACCEPTED",
          "version": 2
        },
        "created_at": "2026-09-03T15:02:00Z"
      }
    ]
  }
  ```
- **Respon Error**:
  - `401 Unauthorized` / `403 Forbidden`: Pengguna tidak memiliki akses role `STAFF`.
  - `404 Not Found`: Pesanan dengan ID tersebut tidak ditemukan.
