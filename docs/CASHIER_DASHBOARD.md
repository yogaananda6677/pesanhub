# PesenHub Cashier Dashboard & Operational Summary

Dokumen ini mendokumentasikan spesifikasi implementasi dashboard kasir dan ringkasan operasional harian pada aplikasi kasir POS/KDS PesenHub ([Issue #25](https://github.com/yogaananda6677/pesanhub/issues/25)).

---

## 1. Latar Belakang & Kebutuhan Desain

Kasir outlet nasi goreng merangkap berbagai tugas fisik (memasak, membungkus pesanan, melayani pelanggan, dan menerima pembayaran). 
Dashboard kasir dirancang dengan prinsip:
1. **Scannable**: Memberikan informasi volume pesanan dalam hitungan detik tanpa membuka banyak layar.
2. **Actionable dalam 1 Tap**: Seluruh aksi utama operasional dapat dijangkau dalam maksimal satu ketukan dari dashboard.
3. **Resilient**: Menampilkan waktu pembaruan data secara transparan serta memberikan peringatan jelas saat data *stale* atau perangkat dalam mode *offline*.
4. **Fokus Operasional**: Hanya menyajikan ringkasan antrean dan status operasional, bukan laporan keuangan atau analitik historis kompleks.

---

## 2. Metrik Operasional (`OperationalSummary`)

Data operasional direpresentasikan sebagai satu snapshot konsisten:

| Metrik | Deskripsi | Aksi Ketuk (1 Tap) | Warna / Semantik |
|---|---|---|---|
| **Menunggu Konfirmasi** | Pesanan masuk dari Web Customer / WhatsApp yang butuh persetujuan kasir | Buka tab **Antrean** | Amber / Warning (`AppColors.statusPending`) |
| **Sedang Dimasak** | Pesanan yang sedang dikerjakan di dapur | Buka tab **Dapur KDS** | Indigo / Preparing (`AppColors.statusPreparing`) |
| **Siap Diambil** | Pesanan selesai masak, siap diserahkan ke pelanggan / kurir | Buka tab **Antrean** | Green / Ready (`AppColors.statusReady`) |
| **Pesanan Terlambat** | Pesanan aktif yang melewati batas toleransi waktu (> 15 menit) | Buka tab **Antrean** | Red / Danger (`AppColors.error`), border alert merah |
| **Selesai Hari Ini** | Total pesanan yang berhasil diselesaikan pada hari berjalan | Buka tab **Antrean** | Slate / Neutral (`AppColors.statusCompleted`) |
| **Antrean Offline** | Pesanan/mutasi lokal yang tersimpan di outbox dan belum tersinkron ke server | Segarkan sinkronisasi | Amber / Warning (`AppColors.warning`) |

---

## 3. Freshness & Stale/Offline Handling (Kriteria #2)

File: `pesenhub_app/lib/dashboard/widgets/freshness_indicator.dart`
- **Indikator Waktu Pembaruan**: Menampilkan format jam:menit (`Terakhir diperbarui: 19:55`).
- **Peringatan Data Usang (*Stale*)**: Menampilkan `AppBanner` warning bertuliskan *"Data Usang: Sambungan ke server belum diperbarui"* dengan tombol refresh.
- **Peringatan Mode Offline**: Menampilkan `AppBanner` warning bertuliskan *"Mode Offline: Menggunakan data lokal. Pesanan baru akan disimpan di outbox."* serta badge jumlah antrean offline.

---

## 4. Alur Aksi Cepat 1-Tap (Kriteria #3)

Di bagian atas dashboard tersedia kartu aksi cepat:
- Tombol **"Buat Pesanan Baru"** (`AppButton` Primary): Langsung beralih ke tab Kasir (POS) dalam 1 tap.
- Tombol **"Lihat Dapur KDS"** (`AppButton` Secondary): Langsung beralih ke tab Dapur (KDS) dalam 1 tap.
- Setiap kartu metrik antrean dapat diketuk untuk langsung membuka daftar antrean atau KDS yang relevan.

---

## 5. Dukungan Status Tampilan (Kriteria #4)

Dashboard mendukung siklus status komprehensif:
1. **Loading State**: Menampilkan `AppLoadingState` saat memuat snapshot dari server atau local database.
2. **Success State**: Menampilkan banner freshness, kartu aksi cepat, dan grid metrik responsif (2 kolom pada mobile, 3 kolom pada tablet).
3. **Empty State**: Menampilkan `AppEmptyState` (*"Tidak Ada Pesanan Aktif"*) saat seluruh antrean bersih, lengkap dengan tombol aksi cepat untuk membuat pesanan baru.
4. **Error State**: Menampilkan `AppErrorState` saat terjadi kegagalan jaringan beserta tombol *"Coba Lagi"* (`onRetry`).

---

## 6. Verifikasi & Pengujian

Telah teruji melalui `test/dashboard_test.dart` (7 test cases):
- **Criteria #1**: Hitungan metrik terverifikasi konsisten dengan snapshot model.
- **Criteria #2**: Verifikasi waktu pembaruan dan banner peringatan stale serta offline.
- **Criteria #3**: Verifikasi navigasi 1-tap ke POS, Antrean, dan KDS.
- **Criteria #4**: Verifikasi status loading, empty, error (retry), serta layout responsif mobile dan tablet tanpa overflow.
