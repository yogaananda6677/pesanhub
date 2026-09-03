# Order Detail, Status Timeline, and Contextual Quick Actions (Issue #29)

Dokumen arsitektur dan implementasi untuk **Issue #29: Implementasi order detail, status timeline, dan contextual quick action** pada aplikasi mobile & tablet PesenHub.

---

## 1. Latar Belakang & Masalah

Pada outlet makanan dan minuman sibuk, staf kasir memiliki peran multi-fungsi: mencatat pesanan, menyiapkan bahan, memasak, meracik minuman barista, membungkus pesanan (*takeaway*), menyerahkan pesanan kepada pelanggan, dan menerima pembayaran.

Ketika mengelola pesanan dalam antrean, staf kasir membutuhkan:
1. Akses cepat ke seluruh detail operasional pesanan tanpa membuka banyak layar.
2. Tepat **satu aksi utama kontekstual** yang sesuai dengan status tahapan pesanan saat ini (mencegah salah pencet tombol atau kesalahan transisi state machine).
3. Pemisahan tegas antara **siklus status pesanan** dan **status pembayaran** (Invarian #7).
4. Penanganan konkurensi versi optimistik (*optimistic concurrency*) saat perangkat lain (misal KDS di dapur) telah mengubah status pesanan.
5. Pembatasan hak akses (*role guard*) agar peran dapur (KDS) atau pelanggan tidak dapat melakukan aksi kasir terlarang.

---

## 2. Pemisahan Siklus Status Pesanan dan Status Pembayaran (Invarian #7 & Kriteria #3)

Sesuai aturan bisnis PesenHub, **status pesanan** dan **status pembayaran** adalah dua domain state yang independen:
- **Order Status**: `PENDING`, `ACCEPTED`, `PREPARING`, `READY_FOR_PICKUP`, `COMPLETED`, `REJECTED`, `CANCELLED`.
- **Payment Status**: `UNPAID`, `PAID`, `FAILED`, `EXPIRED`, `REFUNDED`.

Sebuah pesanan bisa saja sudah `COMPLETED` namun status pembayarannya tetap dicatat, atau pesanan berstatus `PREPARING` namun pelanggan sudah `PAID` terlebih dahulu (misal via QRIS/WhatsApp).

### Implementasi Visual
- Komponen [`OrderStatusTimeline`](file:///home/yoga/Data/Kuliah/PTT_app/pesenhub_app/lib/order/widgets/order_status_timeline.dart): Menampilkan tahapan visual progres pesanan (`Diterima` -> `Memasak` -> `Siap Diambil` -> `Selesai`).
- Komponen [`OrderPaymentCard`](file:///home/yoga/Data/Kuliah/PTT_app/pesenhub_app/lib/order/widgets/order_payment_card.dart): Menampilkan status pembayaran mandiri dengan badge warna (`UNPAID` oranye, `PAID` hijau) beserta total nilai transaksi.

---

## 3. Matriks Aksi Kontekstual Sesuai State dan Peran (Kriteria #1 & #4)

UI menyajikan **tepat satu aksi primer** (`primaryAction`) berbasis state terkini dan peran (*role*) pengguna:

| Current State | Role | Primary Action | Target Status | Secondary Action |
|---|---|---|---|---|
| `PENDING` | `STAFF` | **Terima Pesanan** | `ACCEPTED` | Tolak Pesanan (`REJECTED`) |
| `ACCEPTED` | `STAFF` | **Mulai Masak** | `PREPARING` | Batalkan Pesanan (`CANCELLED`) |
| `PREPARING` | `STAFF` | **Tandai Siap** | `READY_FOR_PICKUP` | - |
| `PREPARING` | `KDS` | **Tandai Siap** | `READY_FOR_PICKUP` | - |
| `READY_FOR_PICKUP` | `STAFF` | **Selesaikan Order** | `COMPLETED` | - |
| `COMPLETED` | Semuanya | *None (Terminal State)* | - | - |
| State Apapun | `CUSTOMER` | *None (Read-Only)* | - | - |
| Non-PREPARING | `KDS` | *None (Kitchen Restricted)* | - | - |

---

## 4. Penanganan Konflik Versi Optimistik (Kriteria #2)

- Setiap pesanan menyertakan nomor versi (`version`, integer meningkat monoton).
- Saat melakukan transisi, controller mengirimkan `expected_version = order.version`.
- Jika server mengembalikan `VERSION_CONFLICT` (HTTP 409 atau error teks serupa):
  1. Transisi dibatalkan secara aman (*aborted*).
  2. Banner peringatan konflik kuning ditampilkan pada UI: *"Konflik Versi: Data pesanan telah diperbarui oleh perangkat atau staf lain."*
  3. Controller memanggil `reloadFn` untuk memuat state terbaru dari server/repository **tanpa menimpa (*without overwrite*)** data di server.

---

## 5. Tata Letak Responsif Mobile & Tablet (Kriteria #5)

- **Mobile (< 600dp)**: Dibuka sebagai bottom sheet modal yang dapat di-scroll vertikal dan mendukung padding keyboard virtual.
- **Tablet (>= 600dp)**: Ditampilkan sebagai dialog terpusat dengan lebar tetap (`maxWidth: 620dp`) untuk efisiensi ruang pandang kasir.
- **Dukungan Teks Dinamis & Ahem Font**: Seluruh baris data dilengkapi pembungkus `Flexible`/`Expanded` dan `TextOverflow.ellipsis` untuk mencegah RenderFlex overflow di layar sempit.

---

## 6. Verifikasi Pengujian

Pengujian otomatis mencakup 6 skenario komprehensif di [`test/order_detail_test.dart`](file:///home/yoga/Data/Kuliah/PTT_app/pesenhub_app/test/order_detail_test.dart):
1. Transisi `PREPARING` menghasilkan aksi *"Tandai Siap"* dengan target `READY_FOR_PICKUP`.
2. Deteksi konflik versi optimistik dan pembaruan data tanpa overwrite.
3. Pemisahan tegas antara timeline status order dan kartu status pembayaran.
4. Role guard membatasi aksi untuk `KDS` dan `CUSTOMER`.
5. Tampilan responsif mobile dan tablet bebas RenderFlex overflow.
6. Penanganan banner error jaringan dan feedback sukses.
