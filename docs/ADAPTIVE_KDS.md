# Adaptive Kitchen Display System (KDS) (Issue #30)

Dokumen arsitektur dan panduan teknis untuk **Issue #30: Implementasi KDS adaptif untuk tablet dan mobile** pada aplikasi POS/KDS PesenHub.

---

## 1. Latar Belakang & Masalah

Di dapur outlet nasi goreng yang sibuk, koki dan staf produksi membutuhkan tampilan yang:
1. Terbaca jelas dari jarak pandang wajan/dapur (ukuran teks dan kontras tinggi).
2. Menampilkan tiket pesanan secara adaptif pada layar tablet (multi-kolom) maupun smartphone (daftar vertikal) tanpa overflow horizontal.
3. Memprioritaskan pesanan terlambat (*overdue* > 15 menit) secara deterministik di posisi teratas, diikuti oleh antrean FIFO.
4. Membedakan secara instan antara makanan dapur (wajan/penggorengan) dan minuman barista.
5. Menampilkan penanda bungkus (*takeaway*) beserta instruksi kemasan khusus pelanggan secara mencolok.
6. Menyediakan aksi status 1-tap yang konsisten dengan kontrak versi (*version contract*) backend dan mencegah penekanan ganda (*double-tap*).

---

## 2. Arsitektur Komponen

```
pesenhub_app/lib/kds/
├── controllers/
│   └── kds_controller.dart        # Pengelolaan tiket dapur, filter status, pengurutan, lock aksi ganda
├── widgets/
│   └── kds_ticket_card.dart       # Komponen tiket dapur dengan banner overdue, sorotan minuman & bungkus, tombol 1-tap
└── kds_view.dart                  # View adaptif: grid responsif multi-kolom di tablet, single-kolom di mobile
```

---

## 3. Matriks Alur & Aksi Cepat 1-Tap (Kriteria #4)

Tiket pada KDS hanya menampilkan pesanan yang berada dalam siklus dapur:

| Status Saat Ini | Label Tombol 1-Tap | Target Status Baru | Perilaku Tiket Setelah Transisi |
|---|---|---|---|
| `ACCEPTED` | **Mulai Masak** | `PREPARING` | Tiket tetap berada di KDS dengan status berubah menjadi Memasak. |
| `PREPARING` | **Tandai Siap** | `READY_FOR_PICKUP` | Tiket selesai dimasak dan meninggalkan layar KDS menuju meja kasir. |

- **Double-Action Guard**: Controller mencatat `_processingOrderIds`. Selama request transisi berjalan, tombol menampilkan label *"Memproses..."* dan dinonaktifkan (`onPressed: null`).
- **Version Contract**: Setiap request transisi menyertakan nomor versi saat ini (`order.version`) untuk menjamin konsistensi konkuren.

---

## 4. Prioritisasi Deterministik & Umur Order (Kriteria #2)

Pengurutan tiket dapur dihitung secara deterministik oleh `KdsController.sortedOrders`:
1. **Prioritas Utama (Overdue First)**: Pesanan yang telah melewati batas 15 menit sejak `createdAt` (`order.isOverdueAt(now)`) ditempatkan paling awal dan diberi banner merah mencolok:
   `TERLAMBAT (> 15 mnt) • [elapsedText]`
2. **Prioritas Berikutnya (FIFO)**: Pesanan yang belum terlambat diurutkan berdasarkan waktu pembuatan (`createdAt` ascending).

---

## 5. Pembedaan Visual Menu & Kemasan (Kriteria #3)

1. **Minuman Barista**:
   - Dikelompokkan dalam kontainer berikon `Icons.local_cafe_rounded` berwarna biru/teal.
   - Memungkinkan barista dan koki wajan membagi tugas tanpa saling menunggu atau salah menyiapkan menu.
2. **Kemasan Bungkus (*Takeaway*)**:
   - Tiket dengan `isTakeaway: true` menampilkan container kuning/oranye kontras dengan label `Bungkus: [catatan kemasan]` (contoh: *"Pisah bumbu & kuah"*).
3. **Level Pedas & Topping**:
   - Catatan makanan yang mengandung kata *"pedas"* otomatis diwarnai merah mencolok (`AppColors.error`) agar koki langsung waspada saat menakar cabai.
   - Badge kuantitas tebal (contoh: `2x`) dengan kontainer warna primer.

---

## 6. Tata Letak Adaptif Tablet & Mobile (Kriteria #1 & #5)

- **Mobile (< 600dp)**: Ditampilkan sebagai `ListView.separated` satu kolom vertikal.
- **Tablet (>= 600dp)**: Ditampilkan sebagai multi-kolom responsif (2 kolom pada layar tablet standar, 3 kolom pada layar lebar >= 960dp) tanpa *horizontal overflow*.
- **Siklus State**:
  - *Empty State*: Menampilkan ilustrasi *"Dapur Bersih! Tidak ada pesanan aktif yang perlu dimasak saat ini."*
  - *Loading State*: Indikator proses *"Memuat tiket dapur..."*.
  - *Error Banner*: Menampilkan pesan galat jaringan/koneksi.
  - *Filter Chips*: Menyaring tiket berdasarkan status: `Semua`, `Perlu Dimasak` (`ACCEPTED`), dan `Sedang Dimasak` (`PREPARING`).

---

## 7. Verifikasi Pengujian

Pengujian otomatis komprehensif di [`test/kds_test.dart`](file:///home/yoga/Data/Kuliah/PTT_app/pesenhub_app/test/kds_test.dart):
- `Criteria #1`: Pengujian layout mobile & tablet bebas RenderFlex overflow.
- `Criteria #2`: Pengujian urutan deterministik (overdue first + FIFO).
- `Criteria #3`: Pengujian visual minuman barista, catatan bungkus, dan level pedas.
- `Criteria #4`: Pengujian aksi 1-tap, kontrak versi, dan pencegahan double-action.
- `Criteria #5`: Pengujian siklus state (Empty, Loading, Error, Filter Chips).
