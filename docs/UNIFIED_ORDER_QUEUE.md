# PesenHub Unified Order Queue, Source Badges & Visual Alerts

Dokumen ini mendokumentasikan spesifikasi implementasi antrean order terpadu (*Unified Order Queue*), badge kanal sumber, dan indikator visual operasional pada aplikasi kasir POS/KDS PesenHub ([Issue #26](https://github.com/yogaananda6677/pesanhub/issues/26)).

---

## 1. Latar Belakang & Kebutuhan Desain

Kasir outlet nasi goreng merangkap berbagai peran fisik (memasak, meracik minuman, membungkus pesanan, dan menerima pembayaran).
Untuk mencegah pesanan terlewat atau terjadi salah olah:
1. **Satu Antrean Terpadu**: Menggabungkan pesanan dari seluruh kanal (WhatsApp, Web Customer, dan Kasir Manual) ke dalam satu daftar kronologis yang stabil.
2. **Identifikasi Kanal Cepat**: Setiap kartu memiliki badge visual yang membedakan sumber pesanan secara instan.
3. **Alert Terlambat (> 15 Menit)**: Pesanan aktif yang belum selesai dalam 15 menit langsung diberi tanda bahaya visual merah agar segera diprioritaskan.
4. **Visibilitas Minuman & Catatan Bungkus**: Minuman disorot dalam blok khusus untuk barista, dan pesanan bungkus (*takeaway*) menampilkan catatan pengemasan tanpa perlu membuka dialog detail baru.
5. **Deduplikasi & Rekoneksi Idempoten**: Penambahan pesanan dari event WebSocket atau snapshot REST dipetakan berdasarkan ID unik dan versi pesanan untuk mencegah kartu ganda.

---

## 2. Badge Kanal Sumber MVP (Kriteria #1)

Menggunakan komponen terstandarisasi `AppStatusBadge.source(...)`:

| Kanal Sumber | Badge Teks | Ikon | Semantik Warna |
|---|---|---|---|
| `WHATSAPP` | **WhatsApp** | `Icons.chat_bubble_outline_rounded` | Hijau WhatsApp (`AppColors.sourceWhatsapp`) |
| `CUSTOMER_WEB` | **Web Customer** | `Icons.language_rounded` | Biru Web (`AppColors.sourceWeb`) |
| `CASHIER_MANUAL` | **Kasir Manual** | `Icons.point_of_sale_rounded` | Oranye Kasir (`AppColors.sourcePos`) |

---

## 3. Deduplikasi & Real-time Event Handling (Kriteria #2)

File: `pesenhub_app/lib/queue/controllers/queue_controller.dart`
- **Penyimpanan Berbasis Map**: Antrean dikelola dalam `Map<String, QueueOrder>` dengan kunci `order.id`.
- **Event Upsert Idempoten**: Saat menerima event pesanan baru (`upsertOrder`):
  - Jika ID belum ada, pesanan ditambahkan ke antrean.
  - Jika ID sudah ada, data diperbarui *in-place* hanya jika `event.version >= existing.version`.
  - Event lawas yang datang terlambat (*out-of-order*) diabaikan sehingga tidak membuat kartu ganda (*zero duplicate cards*).
- **Pemulihan Snapshot**: Saat terjadi rekoneksi jaringan (`setSnapshot`), antrean digantikan secara bersih tanpa mengubah filter aktif kasir.

---

## 4. Alert Visual, Minuman & Catatan Bungkus (Kriteria #3)

File: `pesenhub_app/lib/queue/widgets/order_queue_card.dart`
Setiap kartu antrean menyajikan:
1. **Banner Pesanan Terlambat**:
   - Jika pesanan aktif berumur `>= 15 menit`, batas kartu diberi garis merah 2px dan banner merah *"TERLAMBAT (> 15 MENIT BELUM SELESAI)"* dengan ikon `Icons.timer_off_rounded`.
2. **Sorotan Minuman (Barista)**:
   - Item pesanan dengan `isDrink == true` dikelompokkan dalam kotak biru berikon cangkir (`Icons.local_drink_rounded`) agar minuman dapat langsung disiapkan tanpa menunggu masakan matang.
3. **Bagian Bungkus / Takeaway**:
   - Jika pesanan dibungkus (`isTakeaway == true`), kartu menampilkan badge tas belanja serta catatan khusus pengemasan (misal *"Pisah kuah dan sambal"*).
4. **Tombol Aksi Kontekstual**:
   - `PENDING`: Tombol **"Terima Pesanan"** (Primary) & **"Tolak"** (Danger).
   - `ACCEPTED`: Tombol **"Mulai Masak di Dapur"**.
   - `PREPARING`: Tombol **"Tandai Siap Diambil"**.
   - `READY_FOR_PICKUP`: Tombol **"Serahkan ke Pelanggan"**.

---

## 5. Aturan Pengurutan Stabil (Kriteria #4)

Daftar pesanan (`filteredOrders`) selalu diurutkan secara deterministik:
1. **Pesanan Terlambat Pertama**: Pesanan yang melewati batas 15 menit diletakkan di paling atas.
2. **Prioritas Status Operasional**:
   - `PENDING` (Urutan 0 — butuh konfirmasi kasir).
   - `ACCEPTED` (Urutan 1 — antrean masak).
   - `PREPARING` (Urutan 2 — sedang dimasak).
   - `READY_FOR_PICKUP` (Urutan 3 — siap serah terima).
   - Lainnya / Selesai (Urutan 4).
3. **FIFO Berdasarkan Waktu Pesanan**: Di dalam kelompok status yang sama, pesanan yang dibuat lebih awal (*createdAt ascending*) selalu berada di atas.

---

## 6. Cakupan State & Layout Responsif (Kriteria #5)

File: `pesenhub_app/lib/queue/queue_view.dart`
- **Filter Bar**: Filter status per tab (`Semua`, `Menunggu`, `Dimasak`, `Siap`) dengan badge jumlah order, filter kanal sumber, dan pencarian teks.
- **Loading State**: `AppLoadingState` dengan animasi indikator.
- **Empty State**: `AppEmptyState` dengan ikon struk dan pesan informatif saat antrean bersih.
- **Error State**: `AppErrorState` dengan tombol retry (`onRefresh`).
- **Stale/Offline Banner**: Peringatan saat koneksi WebSocket terputus atau aplikasi bekerja offline.
- **Responsif**: 1 kolom vertikal pada ponsel (< 600dp), 2 kolom seimbang pada tablet (>= 600dp), bebas dari *RenderFlex overflow*.

---

## 7. Verifikasi & Pengujian

Telah teruji melalui `test/queue_test.dart` (7 test cases):
- **Criteria #1**: Verifikasi ketiga sumber MVP menampilkan teks dan ikon badge yang berbeda.
- **Criteria #2**: Verifikasi upsert real-time tidak membuat kartu ganda dan menghormati versioning.
- **Criteria #3**: Verifikasi alert terlambat, minuman terpisah, dan catatan bungkus langsung di kartu.
- **Criteria #4**: Verifikasi stable sort (overdue -> pending FIFO) dan rekoneksi recovery snapshot.
- **Criteria #5**: Verifikasi filter chips, seluruh presentation states (loading, empty, error, stale), serta responsivitas mobile dan tablet.
