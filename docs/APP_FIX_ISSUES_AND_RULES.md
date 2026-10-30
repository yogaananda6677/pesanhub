# PesenHub — Rencana Perbaikan Aplikasi (App Fix Issues & Execution Rules)

Dokumen ini memuat spesifikasi terperinci untuk 4 TODO perbaikan aplikasi PesenHub, lengkap dengan checklist penerimaan (*todo check*), arsitektur teknis, kontrak API, serta aturan baku (*engineering rules*) yang wajib dipatuhi selama implementasi.

---

## DAFTAR ISI
1. [Aturan Baku Pengerjaan TODO (Engineering Rules & SOP)](#1-aturan-baku-pengerjaan-todo-engineering-rules--sop)
2. [Issue 1: Redesign dan Customization UI/UX](#2-issue-1-redesign-dan-customization-uiux)
3. [Issue 2: Cek Profil dan Hubungkan ke Database (Jam Buka & Hari Buka)](#3-issue-2-cek-profil-dan-hubungkan-ke-database-jam-buka--hari-buka)
4. [Issue 3: Menu Riwayat Transaksi & Struk Kasir](#4-issue-3-menu-riwayat-transaksi--struk-kasir)
5. [Issue 4: Modul & Menu Khusus Keuangan (Rekap Kas & Tutup Kasir)](#5-issue-4-modul--menu-khusus-keuangan-rekap-kas--tutup-kasir)
6. [Roadmap & Urutan Eksekusi](#6-roadmap--urutan-eksekusi)

---

## 1. Aturan Baku Pengerjaan TODO (Engineering Rules & SOP)

Semua kontributor, developer, dan coding agent wajib mematuhi aturan berikut tanpa pengecualian:

### 1.1 Invarian Sistem & Arsitektur
1. **Backend Golang adalah System of Record**: Perhitungan harga, diskon, omset, dan transisi status order mutlak diputuskan oleh backend. Aplikasi Flutter dilarang melakukan perhitungan finansial resmi secara terisolasi.
2. **Offline-First dengan Idempotensi**: Transaksi kasir dan perubahan status yang dibuat saat jaringan terputus harus disimpan di SQLite lokal dengan `Idempotency-Key` (UUIDv4) dan disinkronkan otomatis saat online via outbox worker.
3. **Role-Based Access Control (RBAC)**:
   - `SUPERADMIN`: Hanya via portal Web, dilarang mengakses runtime mobile POS/KDS atau data transaksi outlet.
   - `ADMIN` / `OWNER`: Memiliki hak penuh atas konfigurasi cabang, jam buka, diskon, profil gerai, dan laporan keuangan.
   - `CASHIER`: Memiliki hak akses POS, antrean aktif, riwayat transaksi cabang aktif, dan input rekap kasir/shift.
4. **Proteksi PII & Sanitasi**: Nomor WhatsApp dan data kontak pelanggan wajib disanitasi dan di-masking pada audit log dan tampilan publik.
5. **No Hardcoded State**: Nilai konfigurasi gerai (jam buka, status buka/tutup, rekap kas, nama cabang) tidak boleh lagi di-hardcode di view Flutter.

### 1.2 Alur Kerja Git & Kontribusi (`CONTRIBUTING.md`)
1. **Satu Issue, Satu Branch, Satu PR**:
   - Format branch: `feature/<nomor-issue>-<slug-deskriptif>` atau `fix/<nomor-issue>-<slug>`.
   - Dilarang keras push langsung ke branch `main`.
2. **Format Commit & PR**:
   - Mengikuti *Conventional Commits*: `feat(...)`, `fix(...)`, `refactor(...)`, `test(...)`.
   - PR wajib menyertakan closing keyword: `Closes #<nomor-issue>` dan referensi parent `Parent Phase: #6`.
   - PR perubahan UI wajib melampirkan screenshot sebelum dan sesudah.
3. **Quality Gate (100% Pass)**:
   - Backend: `go test ./...` harus 100% lulus tanpa kegagalan.
   - Mobile: `flutter analyze` 0 issues dan `flutter test` 100% lulus.

### 1.3 Standar Desain UI/UX Flutter (`FLUTTER_DESIGN_SYSTEM.md`)
1. **Design Tokens Terpusat**: Seluruh warna wajib merujuk ke `AppColors` (Terracotta `#7A321F`/`#8D321F`, Warm Cream `#FFF8EE`, Surface `#FFFFFF`, Text Primary `#1E293B`). Dilarang menulis raw hex color di widget view.
2. **Target Sentuh Minimum 48x48 dp**: Seluruh tombol, chip, input field, dan ikon aksi wajib memiliki hit target minimal 48 logical pixels untuk kenyamanan kasir di dapur.
3. **Bebas Ketergantungan Warna**: Informasi status tidak boleh hanya mengandalkan warna. Wajib memadukan **label teks eksplisit** + **ikon Material unik**.
4. **Skalabilitas Teks 2.0x**: Semua tata letak wajib lolos uji text scale hingga 200% tanpa error `RenderFlex overflowed`.
5. **Responsif Ponsel (< 600dp) & Tablet (>= 600dp)**: Shell navigasi beradaptasi otomatis antara `NavigationBar` (bottom bar) di layar ponsel dan `NavigationRail` / drawer di layar tablet/POS desktop.

---

## 2. Issue #178: Redesign dan Customization UI/UX

### Metadata Issue
- **Nomor Issue**: [#178](https://github.com/yogaananda6677/pesanhub/issues/178)
- **Judul**: `refactor(ui): peremajaan visual ui/ux, kustomisasi tema terpusat, dan navigasi responsif 5 modul`
- **Labels**: `type:feature`, `area:mobile`, `area:ui`, `phase:1d`, `priority:high`
- **Parent**: Phase 1D (#6)

### Deskripsi & Latar Belakang
Antarmuka kasir saat ini memiliki beberapa inkonsistensi styling: warna hex di-hardcode langsung di beberapa file view (`0xFFFBF8F5`, `0xFF2D231E`), navigasi utama `AppDestination` hanya memfasilitasi 4 menu (Beranda, Kasir, Transaksi, Akun), dan belum tersedia kustomisasi branding visual gerai. Diperlukan pembaruan UI/UX menyeluruh yang lebih modern, elegan, ergonomis untuk layar kasir/tablet, serta mendukung penambahan tab menu baru tanpa kepadatan visual (*visual clutter*).

### Spesifikasi Teknis
1. **Refactoring Token Desain**:
   - Rapikan seluruh palet warna ke `AppColors` (palette terracotta martabak, warm cream background, slate text).
   - Standardisasi `AppSpacing` (grid 4dp) dan `AppRadius` (8dp input, 12dp card, 16dp sheet/dialog).
   - Tambahkan utility shimmer/skeleton loading saat memuat data.
2. **Navigasi Shell Adaptif (`AppShell` & `AppDestination`)**:
   - Perbarui enum `AppDestination` untuk mengakomodasi 5 modul inti:
     1. `dashboard` (Beranda)
     2. `pos` (Kasir)
     3. `queue` (Antrean Dapur)
     4. `history` (Riwayat Transaksi)
     5. `finance` (Keuangan & Rekap Kas)
   - Menu Akun/Pengaturan diakses melalui avatar/icon button di AppBar atas atau menu sekunder terpadu.
   - Pada layar tablet (`width >= 600`), navigasi menggunakan `NavigationRail` yang ramping dengan label kompak.
   - Pada layar ponsel (`width < 600`), navigasi menggunakan `NavigationBar` Material 3 dengan badge notifikasi antrean aktif.
3. **Kustomisasi Tema & Tampilan Gerai**:
   - Tambahkan `BrandThemeConfig` di settings untuk menyesuaikan identitas gerai (nama display, logo gerai, dan aksen warna opsional).
   - Mikro-interaksi taktil: Haptic feedback ringan saat aksi keranjang POS dan perubahan status order.

### Todo Checklist (Kriteria Penerimaan)
- [ ] Enum `AppDestination` diperluas mencakup `dashboard`, `pos`, `queue`, `history`, `finance`.
- [ ] `AppShell` mendukung navigasi responsif ponsel (`NavigationBar`) dan tablet (`NavigationRail`) tanpa layout overflow.
- [ ] Semua kode warna hardcoded di `outlet_operational_view.dart`, `financial_report_sheet.dart`, `dashboard_view.dart` dimigrasikan ke `AppColors`.
- [ ] Komponen kartu, banner hero, dan dialog menggunakan elevasi dan radius konsisten (`AppRadius.md: 12dp`, `AppRadius.lg: 16dp`).
- [ ] Seluruh tombol dan tap target memenuhi syarat ergonomi minimum 48x48 dp.
- [ ] Empty state visual yang estetik untuk antrean kosong, riwayat kosong, dan laporan keuangan baru.
- [ ] Uji responsif matrix layar (compact-360dp, mobile-390dp, tablet-768dp, desktop-1280dp) lulus 100% pada text scale 1.0x dan 2.0x.

---

## 3. Issue #179: Cek Profil dan Hubungkan ke Database (Jam Buka & Hari Buka)

### Metadata Issue
- **Nomor Issue**: [#179](https://github.com/yogaananda6677/pesanhub/issues/179)
- **Judul**: `feat(profile): integrasi database profil gerai, sinkronisasi jam dan hari buka operasional realtime`
- **Labels**: `type:feature`, `area:backend`, `area:mobile`, `phase:1d`, `priority:high`
- **Parent**: Phase 1D (#6)

### Deskripsi & Latar Belakang
Halaman profil dan operasional gerai (`OutletOperationalView`) saat ini masih menggunakan data palsu (*hardcoded state*): status `_isOpen = true`, jam buka `'16:00 - 23:30'`, dan hari buka `'Setiap Hari'`. Tombol switch buka/tutup hanya menampilkan `SnackBar` lokal tanpa tersimpan ke database. Di sisi backend, model `Branch` belum memiliki kolom konfigurasi jam dan hari operasional, serta agen bot WhatsApp Hermes belum dapat membaca jam operasional dinamis dari database saat pelanggan bertanya.

### Spesifikasi Teknis
1. **Backend Database & Model (`pesenhub_be`)**:
   - Tambahkan kolom pada tabel `branches`:
     - `open_time VARCHAR(10) DEFAULT '16:00'`
     - `close_time VARCHAR(10) DEFAULT '23:30'`
     - `open_days VARCHAR(255) DEFAULT 'SENIN,SELASA,RABU,KAMIS,JUMAT,SABTU,MINGGU'`
     - `is_open BOOLEAN DEFAULT TRUE`
   - Buat migrasi MySQL di `pesenhub_be/migrations/`.
   - Perbarui struct `Branch`, `CreateBranchInput`, dan `UpdateBranchInput` di `internal/branch/model.go`.
2. **API Endpoint Operasional Gerai**:
   - `GET /api/v1/branches/current` atau `GET /api/v1/outlet/profile`: Mendapatkan konfigurasi outlet aktif.
   - `PUT /api/v1/branches/:id/operational`: Memperbarui status buka/tutup, jam buka, jam tutup, dan hari operasional. Wajib divalidasi dengan format `HH:MM` dan otorisasi `CanManageOutlet`.
3. **Integrasi Hermes AI CS Bot**:
   - Perbarui handler intent `internal/hermes/cs_intents.go` untuk membaca jam buka dan hari buka dari database aktif, bukan teks statis.
4. **Frontend Flutter (`pesenhub_app`)**:
   - Buat `OutletProfileController` dan model data profil gerai.
   - Sambungkan `OutletOperationalView` ke `PesenHubApiClient`.
   - Implementasikan dialog pemilih waktu (`showTimePicker`) untuk jam buka dan jam tutup.
   - Implementasikan selector hari operasional berbasis FilterChip (Senin – Minggu).
   - Switch "Status Layanan Kasir" memicu mutasi API dengan *optimistic update* dan rollback jika gagal.
   - Simpan snapshot profil ke SQLite lokal agar tetap bisa dibaca saat offline.

### Todo Checklist (Kriteria Penerimaan)
- [ ] Skema database `branches` memiliki kolom `open_time`, `close_time`, `open_days`, dan `is_open`.
- [ ] Migrasi database MySQL dan SQLite lokal berjalan sukses tanpa merusak data lama.
- [ ] Endpoint `PUT /api/v1/branches/:id/operational` mengembalikan data tervalidasi dan mencatat audit log.
- [ ] Bot Hermes WhatsApp menjawab pertanyaan jam operasional sesuai data realtime di database.
- [ ] Halaman `OutletOperationalView` menampilkan data profil asli yang ditarik dari backend saat dibuka.
- [ ] Kasir/Owner dapat mengubah jam buka, jam tutup, dan hari buka dengan konfirmasi tersimpan ke database.
- [ ] Switch Buka/Tutup memperbarui status gerai secara realtime dan tersinkronisasi antar perangkat.
- [ ] Mode offline menampilkan data tersimpan dari cache SQLite lokal tanpa layar blank/error.
- [ ] Unit test backend (`branch_test.go`) dan widget test Flutter (`outlet_operational_view_test.dart`) lulus 100%.

---

## 4. Issue #180: Menu Riwayat Transaksi & Struk Kasir

### Metadata Issue
- **Nomor Issue**: [#180](https://github.com/yogaananda6677/pesanhub/issues/180)
- **Judul**: `feat(history): penambahan menu riwayat transaksi, pencarian pesanan, detail struk, dan cetak ulang`
- **Labels**: `type:feature`, `area:mobile`, `area:backend`, `phase:1d`, `priority:high`
- **Parent**: Phase 1D (#6)

### Deskripsi & Latar Belakang
Saat pesanan selesai diproses (`COMPLETED`) atau dibatalkan (`CANCELLED`), pesanan tersebut hilang dari tampilan antrean aktif (`QueueView`). Kasir dan pemilik gerai saat ini tidak memiliki menu khusus untuk meninjau riwayat transaksi masa lalu, mencari bukti transaksi berdasarkan nomor HP atau ID pesanan, mencetak ulang struk fisik, atau mengecek alasan pembatalan order.

### Spesifikasi Teknis
1. **Backend Query & Indexing (`pesenhub_be/internal/order`)**:
   - Pastikan endpoint `GET /api/v1/orders` mendukung filter status riwayat (`COMPLETED`, `CANCELLED`, `REJECTED`), rentang waktu (`created_from`, `created_to`), pencarian teks (`search` untuk Order ID, nama pelanggan, no. HP), serta pagination (`limit`, `offset`).
   - Pastikan indeks komposit di tabel `orders` pada kolom `(branch_id, status, created_at)` tersedia untuk performa query data historis yang cepat.
2. **Frontend Arsitektur Menu Riwayat (`pesenhub_app`)**:
   - Buat folder `lib/history/` dengan struktur:
     - `controllers/history_controller.dart`
     - `models/history_filter.dart`
     - `views/history_view.dart`
     - `widgets/history_order_card.dart`
     - `widgets/history_filter_sheet.dart`
     - `widgets/order_receipt_modal.dart`
3. **Fitur Antarmuka Riwayat**:
   - **Search Bar**: Pencarian instan berdasarkan Order ID (contoh: `#ORD-001`), nama pelanggan, atau no. WhatsApp.
   - **Filter Tanggal Cepat**: Chip filter "Hari Ini", "Kemarin", "7 Hari Terakhir", "Bulan Ini", dan "Pilih Rentang Tanggal".
   - **Filter Status & Metode Pembayaran**: Filter chip untuk status Lunas/Batal dan metode Tunai/QRIS Midtrans.
   - **Detail Riwayat & Struk Modal**:
     - Rincian item menu, varian martabak, pilihan kuota topping, level kepedasan, catatan pesanan, dan rincian diskon.
     - Ringkasan pembayaran (metode, waktu bayar, kode referensi).
     - Timeline jejak waktu audit (Waktu dibuat, diterima, dimasak, dan selesai).
     - Tombol **Cetak Ulang Struk** via printer Bluetooth thermal ESC/POS.

### Todo Checklist (Kriteria Penerimaan)
- [ ] Menu `Riwayat` terdaftar di `AppDestination` dan dapat diakses dari navigasi utama.
- [ ] Daftar transaksi selesai dan dibatalkan tampil rapi dengan pagination / infinite scrolling.
- [ ] Fitur pencarian berdasarkan ID pesanan, nama, dan nomor HP berfungsi instan dan akurat.
- [ ] Filter rentang tanggal (Hari ini, 7 hari, 30 hari, kustom) menyaring data dengan benar.
- [ ] Mengetuk kartu pesanan membuka modal rincian transaksi lengkap dan format struk digital.
- [ ] Tombol cetak ulang struk mengirim perintah print format ESC/POS ke printer Bluetooth yang terhubung.
- [ ] Pesanan dibatalkan menampilkan alasan pembatalan dan siapa staf/sistem yang membatalkan.
- [ ] Widget test dan controller unit test riwayat mencakup skenario muat data, filter tanggal, pencarian, dan cetak struk dengan kelulusan 100%.

---

## 5. Issue #181: Modul & Menu Khusus Keuangan (Rekap Kas & Tutup Kasir)

### Metadata Issue
- **Nomor Issue**: [#181](https://github.com/yogaananda6677/pesanhub/issues/181)
- **Judul**: `feat(finance): modul khusus laporan keuangan, rekap kas laci harian, breakdown kanal omset, dan tutup kasir`
- **Labels**: `type:feature`, `area:mobile`, `area:backend`, `phase:1d`, `priority:high`
- **Parent**: Phase 1D (#6)

### Deskripsi & Latar Belakang
Informasi keuangan saat ini hanya berupa kartu ringkas di dashboard dan bottom sheet sementara `FinancialReportSheet` yang masih menggunakan perkiraan kalkulasi statis (misal fallback 60% QRIS). Kasir dan pemilik gerai membutuhkan modul keuangan khusus yang komprehensif untuk memantau omset riil, rincian pembayaran tunai vs QRIS, total diskon yang diberikan, rekap kas laci kasir (pembukuan modal awal, penerimaan kas, pengeluaran kas kecil, dan selisih fisik), serta cetak laporan tutup kasir harian (*end-of-day shift closing*).

### Spesifikasi Teknis
1. **Backend Laporan & Shift Rekonsiliasi (`pesenhub_be`)**:
   - Perbarui `internal/report`:
     - Tambahkan kalkulasi omset riil tanpa estimasi:
       - `GrossRevenue` (Omset kotor sebelum diskon)
       - `TotalDiscount` (Total potongan diskon promo dan manual)
       - `NetRevenue` (Omset bersih aktual yang diterima)
       - `CashRevenue` (Total pembayaran tunai sah)
       - `DigitalRevenue` (Total pembayaran QRIS/Midtrans settled)
       - `AverageOrderValue` (Rata-rata belanja per pesanan)
     - Buat tabel `cash_shifts` untuk manajemen kas laci kasir:
       - `id`, `branch_id`, `cashier_id`, `shift_start`, `shift_end`, `starting_cash` (modal laci kasir), `expected_cash` (modal awal + tunai masuk), `actual_cash` (penghitungan fisik saat tutup), `discrepancy` (selisih lebih/kurang), `notes`, `status` (`OPEN`, `CLOSED`).
     - Endpoint:
       - `GET /api/v1/reports/financial-summary`: Laporan keuangan terperinci sesuai rentang tanggal.
       - `GET /api/v1/reports/top-products`: 5 menu dan topping dengan kontribusi omset tertinggi.
       - `POST /api/v1/shifts/open`: Buka kasir dengan input kas modal awal.
       - `POST /api/v1/shifts/close`: Tutup kasir dengan hitung kas fisik dan audit selisih.
       - `GET /api/v1/shifts/current`: Mengambil status shift kasir yang sedang aktif.
2. **Frontend Modul Keuangan (`pesenhub_app`)**:
   - Buat folder `lib/finance/` dengan struktur:
     - `controllers/finance_controller.dart`
     - `controllers/cash_shift_controller.dart`
     - `models/financial_summary.dart`
     - `models/cash_shift.dart`
     - `views/finance_view.dart`
     - `widgets/revenue_stat_cards.dart`
     - `widgets/payment_breakdown_card.dart`
     - `widgets/top_selling_products_card.dart`
     - `widgets/cash_reconciliation_dialog.dart`
     - `widgets/print_daily_recap_dialog.dart`
3. **Fitur Antarmuka Keuangan**:
   - **Header Filter Periode**: Hari Ini, Kemarin, Minggu Ini, Bulan Ini, dan Kustom.
   - **Kartu Metrik Utama**: Omset Bersih, Total Transaksi Sukses, Rata-rata Nilai Pesanan, dan Total Diskon Promo.
   - **Breakdown Metode Pembayaran**: Visualisasi porsi pembayaran Tunai vs QRIS dengan indikator nominal dan persentase.
   - **Breakdown Kanal Penjualan**: Porsi omset dari Kasir POS Manual, WhatsApp Hermes, dan Web Customer.
   - **Manajemen Kas Laci Kasir (Shift Register)**:
     - Form input modal awal kasir saat mulai bertugas.
     - Ringkasan penerimaan uang fisik di laci kasir secara realtime.
     - Tombol **Tutup Kasir & Rekonsiliasi**: Kasir menghitung uang fisik di laci, sistem menghitung selisih otomatis (*cash discrepancy*), dan meminta catatan jika terjadi selisih.
   - **Cetak Laporan Tutup Kasir**: Cetak ringkasan rekap shift ke printer Bluetooth thermal kasir atau ekspor ringkasan teks ke WhatsApp Owner.

### Todo Checklist (Kriteria Penerimaan)
- [ ] Menu `Keuangan` terdaftar di `AppDestination` dan dapat diakses dengan mudah oleh Admin/Kasir.
- [ ] Ringkasan omset menampilkan data riil dari backend tanpa rumus estimasi persentase buatan.
- [ ] Breakdown metode pembayaran menampilkan pemisahan Tunai dan QRIS Midtrans yang akurat.
- [ ] Terdapat visualisasi porsi omset berdasarkan kanal (Kasir POS, WhatsApp, Web Customer).
- [ ] Kasir dapat membuka shift dengan menginput kas awal di laci kasir.
- [ ] Kasir dapat menutup shift di akhir hari dengan memasukkan total fisik uang kasir dan mendeteksi selisih.
- [ ] Widget daftar 5 menu terlaris tampil dengan jumlah porsi dan kontribusi pendapatan.
- [ ] Fitur Cetak Rekap Harian mencetak struk penutupan kasir ke printer Bluetooth thermal secara rapi.
- [ ] Data tersimpan aman di database backend dengan audit log transparan dan riwayat shift terdahulu.
- [ ] Seluruh unit test backend (`report_test.go`, `shift_test.go`) dan widget test Flutter (`finance_view_test.dart`) lulus 100%.

---

## 6. Roadmap & Urutan Eksekusi

Untuk menjaga stabilitas kode dan kemudahan integrasi, eksekusi 4 TODO dianjurkan mengikuti urutan dependensi berikut:

```text
[Issue 2: Profil & Jam Buka] ──► Menghilangkan hardcode profil & menyiapkan API operasional
             │
             ▼
[Issue 1: Redesign UI/UX]    ──► Memperbarui token desain, AppColors, dan menambahkan tab navigasi
             │
             ├──────────────────────────┐
             ▼                          ▼
[Issue 3: Menu Riwayat]      [Issue 4: Menu Keuangan & Rekap Kas]
(Query order riil & struk)    (Kalkulasi omset, breakdown & shift laci)
             │                          │
             └──────────────────────────┘
                         │
                         ▼
             [Validasi E2E & UAT Final]
```

1. **Sprint 1 — Pondasi Database & Operasional Gerai (Issue 2)**:
   - Selesaikan migrasi database `branches` dan endpoint jam buka backend.
   - Hubungkan `OutletOperationalView` ke backend dan verifikasi bot WhatsApp Hermes.
2. **Sprint 2 — Redesign Visual & Shell Navigasi Adaptif (Issue 1)**:
   - Rapikan `AppColors` dan token desain.
   - Perluas `AppDestination` dan `AppShell` untuk mendukung 5 modul utama di ponsel & tablet.
3. **Sprint 3 — Modul Riwayat Transaksi & Struk (Issue 3)**:
   - Bangun `HistoryController` dan `HistoryView`.
   - Hubungkan query filter riwayat, modal struk, dan integrasi cetak ulang Bluetooth.
4. **Sprint 4 — Modul Khusus Keuangan & Tutup Kasir (Issue 4)**:
   - Selesaikan endpoint laporan keuangan dan tabel `cash_shifts` di backend.
   - Bangun `FinanceView`, rekonsiliasi kas laci kasir, dan cetak struk tutup shift harian.
5. **Sprint 5 — UAT & Regression Testing**:
   - Jalankan `go test ./...` dan `flutter test` untuk memverifikasi 0 regresi.
   - Perbarui `PRD.md` dan `MEMORY.md` sesuai hasil implementasi.
