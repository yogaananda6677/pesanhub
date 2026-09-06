# POS Redesign: Tab Kategori dan Sticky Bottom Cart

## Ringkasan (Issue #133)

Dokumen ini mendokumentasikan redesign antarmuka Point of Sale (POS) PesenHub untuk kasir mobile dan tablet sesuai **Issue #133** (Parent Epic: **#129**, Parent Phase: **#6 / Phase 1D**).

Redesign ini memindahkan fokus kasir di perangkat mobile langsung ke katalog menu, memindahkan identitas pelanggan dan opsi kemasan ke langkah checkout/cart bottom sheet, menghadirkan tab kategori horizontal bergaya modern, serta menyediakan sticky bottom cart bar yang responsif dan bebas overflow di berbagai form factor layar dan skala teks.

---

## 1. Arsitektur & Perubahan Komponen

### A. Compact Header (`MenuCatalogView`)
- **Search Bar**: Input pencarian real-time dengan debounce 250ms dan tombol hapus pencarian (*clear button*) yang muncul saat field terisi (`_searchController.text.isNotEmpty`).
- **Status Konektivitas**: Terintegrasi langsung di sebelah search field menggunakan `ConnectivityBadge` (online/offline/syncing). Kasir mendapatkan visibilitas status jaringan tanpa memakan ruang vertikal berlebih.
- **Konsistensi State**: Menggunakan `GlobalKey` di `_PosViewState` agar instance `MenuCatalogView` tidak di-destroy saat transisi breakpoint mobile $\leftrightarrow$ tablet.

### B. Tab Kategori Horizontal (`MenuCategoryFilter`)
- Menggantikan filter chip vertikal/dropdown lama dengan tab horizontal scrollable (`ListView.separated`) yang mengacu pada `design/index.html`.
- **Kategori "Semua"**: Menampilkan total seluruh menu (misal: `Semua (6)`), diikuti tab kategori backend dinamis (misal: `Makanan (3)`, `Minuman (2)`, `Paket (1)`).
- **Indikator Status Aktif/Inaktif**:
  - Aktif: Latar belakang `AppColors.primary` (hijau forest `#197A56`), teks tebal putih `AppColors.onPrimary`.
  - Inaktif: Latar belakang `AppColors.surface` dengan border `AppColors.border`, teks `AppColors.textPrimary`.
- **Aksesibilitas & Ergonomi**: Minimum touch target $\ge 48\,\text{dp}$ (`constraints: BoxConstraints(minHeight: 48.0)`), padding nyaman, dan indikator semantik untuk screen reader.
- **Isolasi State**: Berpindah tab kategori mempertahankan item keranjang, identitas pelanggan yang sedang diketik, dan teks pencarian.

### C. Fokus Katalog Menu & Item Habis
- Menu cards langsung tampak di baris teratas layar mobile tanpa terdorong oleh formulir pelanggan.
- Menu yang berstatus `isAvailable == false` (habis) tampil dinamis dengan status `disabled`, visual opacity 0.55, badge merah "Habis", dan interaksi tap terkunci untuk mencegah kasir memilih item yang tidak tersedia.

### D. Sticky Bottom Cart Bar (Mobile)
- Muncul secara otomatis saat keranjang memiliki $\ge 1$ item (`_cartController.totalItemCount > 0`).
- Menyajikan ringkasan ringkas:
  - Jumlah item (misal: `1 Item di Keranjang`).
  - Total harga (misal: `Rp 25.000`).
  - Tombol aksi utama "Review Pesanan" dengan touch target $\ge 48\,\text{dp}$.
- Menggunakan padding responsif di bagian bawah katalog (`itemCount > 0 ? 96.0 : AppSpacing.lg`) sehingga kartu menu paling bawah tidak tertutup oleh floating bar.
- Disusun secara responsif menggunakan `Wrap`/`Column` adaptif jika text scale tinggi ($\ge 1.4\times$) atau layar sempit agar tidak pernah mengalami `RenderFlex overflow`.

### E. Mobile Checkout Bottom Sheet (`_showMobileCartSheet`)
- Membuka formulir checkout yang rapi saat sticky bar atau tombol "Review Pesanan" ditekan:
  - **Identitas Pelanggan**: Field wajib `Nama Pelanggan *` dan opsional `Nomor WhatsApp`.
  - **Opsi Layanan**: Toggle switch `Bungkus / Takeaway` dan input catatan kemasan saat aktif.
  - **Daftar Menu Pesanan**: Item list dengan quantity stepper ($+$/$-$), rincian modifier/topping, dan catatan khusus per item.
  - **Review & Proses Pesanan**: Validasi nama pelanggan wajib diisi sebelum lanjut ke `OrderReviewDialog`.
- Dibungkus dengan `ListenableBuilder(listenable: _cartController)` agar perubahan item secara live langsung tercermin di bottom sheet.

### F. Tablet Split-Screen Layout ($\ge 600\,\text{dp}$)
- Layout dua kolom berdampingan:
  - **Kolom Kiri (Flex 6 / 60%)**: Katalog menu penuh dengan search bar dan tab kategori.
  - **Kolom Kanan (Flex 4 / 40%)**: Panel keranjang langsung (*live cart*) mencakup formulir pelanggan, toggle takeaway, daftar menu, ringkasan harga, dan tombol checkout.
- Sticky bottom bar otomatis disembunyikan pada tablet karena keranjang sudah selalu terlihat di sisi kanan.

---

## 2. Pencegahan Overflow & Pengujian Responsif

Semua komponen dialog, kartu, badge, dan layout telah diuji dan dioptimalkan:
- **`OrderReviewDialog`**: Baris identitas pelanggan, nomor WhatsApp, dan badge jenis layanan dibungkus `Flexible` dengan `TextOverflow.ellipsis`.
- **`OrderSuccessDialog`**: Baris kanal sumber (`AppStatusBadge`), pelanggan, layanan, dan total harga dibungkus `Flexible` dengan `TextOverflow.ellipsis`.
- **`PosView` Cart Panel**: Header dan footer total menggunakan layout adaptif berbasis lebar dan text scale.
- **Matrix Pengujian**:
  - `compact-360` ($360 \times 800$) pada text scale $1.0\times$ dan $2.0\times$: **LULUS**.
  - `mobile-390` ($390 \times 844$) pada text scale $1.0\times$ dan $2.0\times$: **LULUS**.
  - `tablet-768` ($768 \times 1024$) pada text scale $1.0\times$ dan $2.0\times$: **LULUS**.
  - `desktop-1280` ($1280 \times 800$) pada text scale $1.0\times$ dan $2.0\times$: **LULUS**.

---

## 3. Persona & Batasan Lingkup

- Aplikasi ini dirancang khusus untuk persona **Kasir** di outlet.
- Tidak mengekspos persona Pemilik/Owner atau Operator pusat.
- Tidak mengekspos konfigurasi teknis gateway WhatsApp, prompt Hermes, atau API keys.
- Status konektivitas menampilkan kejujuran sistem (Online/Offline/Syncing) tanpa menipu status Wi-Fi dengan status backend.

---

## 4. Bukti Validasi

1. **Unit & Widget Tests (`pesenhub_app`)**:
   - `test/pos_redesign_test.dart`: 7 pengujian skenario lengkap (Header, category switching, mobile catalog focus, sticky cart, bottom sheet checkout, tablet split view, responsive matrix) — **SEMUA LULUS**.
   - `test/app_shell_test.dart`: 6 pengujian responsive breakpoints & state preservation — **SEMUA LULUS**.
   - Seluruh test suite `flutter test`: **214 tests PASSED**.
2. **Static Analysis & Formatting**:
   - `flutter analyze`: **No issues found**.
   - `dart format --output=none --set-exit-if-changed .`: **Clean / formatted**.
3. **Backend Verifikasi**:
   - `pesenhub_be/run.sh check`: **LULUS**.

