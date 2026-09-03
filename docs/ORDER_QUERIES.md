# Order Queries, Filtering, and Queue Read Models

PesenHub menyediakan model baca tunggal (unified read model) untuk seluruh pesanan yang berasal dari tiga kanal: `CASHIER_MANUAL`, `CUSTOMER_WEB`, dan `WHATSAPP`.

## 1. Unified Read Model

Seluruh pesanan disajikan dalam representasi yang konsisten:
- **Header Pesanan**: `id`, `order_number`, `client_order_id`, `customer_id`, `source`, `status`, `customer_name`, `customer_phone`, `notes`, `total_amount`, `version`, `created_at`, `updated_at`.
- **Item Pesanan (`items`)**: `id`, `menu_id`, `name`, `sku`, `category_name` (e.g. `Makanan` / `Minuman` untuk routing stasiun KDS), `quantity`, `unit_price_amount`, `line_total_amount`, `notes` (catatan per item), dan `modifiers` (`id`, `name`, `price_delta_amount`).
- **Riwayat Status (`history`)**: Tersedia pada endpoint detail `GET /api/v1/orders/{id}` mencatat transisi status, aktor, reason code, dan timestamp.

---

## 2. Keamanan dan Redaksi PII Berbasis Peran (RBAC)

Endpoint pemuatan pesanan hanya dapat diakses oleh principal yang terotorisasi:
- **`STAFF` (Kasir / Admin)**: Memiliki akses penuh ke seluruh field pesanan, termasuk nomor telepon pelanggan (`customer_phone`) dan identitas pelanggan (`customer_id`).
- **`KDS` (Dapur / Kitchen Display System)**: Mengikuti prinsip *least privilege* dan perlindungan privasi. Field sensitif pelanggan diredaksi:
  - `customer_phone` disetel `null` / dihilangkan.
  - `customer_id` dikosongkan.
  - `customer_name` tetap dipertahankan untuk memanggil pelanggan saat pesanan siap.
- **Peran lain / Tanpa Autentikasi**: Ditolak dengan `403 FORBIDDEN` / `401 UNAUTHENTICATED`.

---

## 3. Query Filtering & Keyset Pagination

### Parameter Filter `GET /api/v1/orders`:
- `status`: Memfilter berdasarkan status pesanan (e.g. `?status=ACCEPTED` atau `?status=ACCEPTED,PREPARING`).
- `source`: Memfilter berdasarkan kanal order (`?source=CASHIER_MANUAL`, `?source=CUSTOMER_WEB`, `?source=WHATSAPP`).
- `created_from` & `created_to`: Rentang waktu RFC3339 (e.g. `?created_from=2026-09-01T00:00:00Z&created_to=2026-09-03T23:59:59Z`).
- `sort`: `created_at` (ascending, default) atau `-created_at` (descending).
- `page[size]`: Jumlah item per halaman (1–100, default 20).
- `page[cursor]`: Cursor berbasis `(created_at, id)` yang di-encode base64 RawURL.

### Keyset Cursor:
Pagination bersifat deterministik dan mencegah duplikasi maupun record terlewat antarhalaman meskipun terjadi penambahan pesanan baru:
- Jika halaman berikutnya tersedia, metadata response mengembalikan `page.next_cursor`.
- Jika berada di halaman terakhir, `page.next_cursor` bernilai `null`.

---

## 4. Snapshot Antrean KDS (`GET /api/v1/orders/queue`)

Digunakan oleh Kitchen Display System untuk mengambil snapshot antrean aktif:
- Hanya mencakup pesanan berstatus aktif: `ACCEPTED`, `PREPARING`, `READY_FOR_PICKUP`.
- Diurutkan secara kronologis (`created_at ASC, id ASC`) agar urutan memasak adil (FIFO).
- Informasi kategori (`category_name`) memisahkan hidangan dapur dan racikan stasiun minuman.
- Catatan pesanan (`notes`) dan catatan per item menampilkan instruksi khusus (seperti "bungkus terpisah" atau "pedas sedang").
