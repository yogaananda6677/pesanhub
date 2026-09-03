# PesenHub Responsive App Shell Architecture

Dokumen ini mendokumentasikan spesifikasi arsitektur navigasi adaptif (*App Shell*) pada aplikasi kasir (POS) dan dapur (KDS) PesenHub ([Issue #24](https://github.com/yogaananda6677/pesanhub/issues/24)).

---

## 1. Latar Belakang & Kebutuhan Desain

Kasir dan koki beroperasi menggunakan perangkat yang bervariasi:
- Ponsel kasir genggam (portrait, layar 360–420 dp).
- Ponsel kasir landscape (mode meja).
- Tablet dapur KDS (layar 800–1280 dp, landscape atau portrait).

Perpindahan orientasi layar, pembukaan keyboard virtual, dan pergantian ukuran window tidak boleh:
1. Menyebabkan *RenderFlex overflow*.
2. Mereset atau menghilangkan input data yang sedang diketik kasir (nama pelanggan, nomor HP, dsb).
3. Menggeser tab aktif secara tidak sengaja.
4. Menutupi tombol aksi utama saat keyboard virtual muncul.

---

## 2. Destinasi Navigasi (`AppDestination`)

Terdapat 5 destinasi utama yang didefinisikan dalam `pesenhub_app/lib/navigation/app_destination.dart`:

| Destinasi | Label | Ikon Normal | Ikon Aktif | Judul Header |
|---|---|---|---|---|
| `pos` | Kasir | `point_of_sale_outlined` | `point_of_sale_rounded` | Kasir — Buat Pesanan |
| `queue` | Antrean | `receipt_long_outlined` | `receipt_long_rounded` | Antrean Pesanan |
| `kds` | Dapur KDS | `outdoor_grill_outlined` | `outdoor_grill_rounded` | Dapur KDS — Tiket Memasak |
| `menu` | Menu | `restaurant_menu_outlined` | `restaurant_menu_rounded` | Kelola Ketersediaan Menu |
| `settings` | Pengaturan | `settings_outlined` | `settings_rounded` | Pengaturan Outlet |

---

## 3. Pola Layout Adaptif Berdasarkan Breakpoint

Menggunakan breakpoint `AppSpacing.tabletBreakpoint = 600.0 dp`:

### 3.1 Mobile Viewport (< 600 dp)
- **Top Header**: Menampilkan judul layar aktif, nama outlet, dan badge status konektivitas (`Online` / `Offline`).
- **Body**: Konten destinasi terpilih (`IndexedStack`).
- **Bottom Navigation Bar**: Menggunakan `NavigationBar` Material 3 dengan target sentuh >= 48px per item, label teks, dan ikon.

### 3.2 Tablet Viewport (>= 600 dp)
- **Navigation Rail**: Bilah navigasi permanen di sisi kiri (`minWidth: 80 dp`) berisi:
  - Header branding logo mangkuk nasi goreng PesenHub.
  - Item destinasi vertikal dengan ikon dan label teks ringkas.
  - Footer indikator konektivitas awan / server.
- **Divider**: Garis batas pemisah halus (`VerticalDivider: 1px`).
- **Main Area**: Header layar + konten destinasi terpilih (`IndexedStack`).

---

## 4. Retensi State Tanpa Reset (State Preservation)

Fulfills **Acceptance Criteria #2**:
1. **Pohon Widget Stabil**: Menggunakan satu `Scaffold` tunggal adaptif di mana `Column -> [Header, Expanded -> IndexedStack]` berada pada posisi pohon yang sama baik pada mode mobile maupun tablet.
2. **`GlobalKey` pada `IndexedStack`**: Memberikan jaminan reparenting Flutter sehingga `State` internal (seperti `TextEditingController`, scroll offset `PageStorageKey`, dan form input) tidak pernah di-dispose saat rotasi orientation (portrait <-> landscape) atau resize window.

---

## 5. Ergonomi Keyboard & System Insets

Fulfills **Acceptance Criteria #3**:
1. `resizeToAvoidBottomInset: true` diaktifkan pada level `Scaffold`.
2. Tampilan form dibungkus dengan `SingleChildScrollView` dan `SafeArea` agar elemen input dan tombol aksi utama (*"Simpan dan Proses Pesanan"*) dapat digulir ke atas saat keyboard virtual menutupi bagian bawah layar.
3. Seluruh baris data menggunakan `Wrap` atau `Expanded` agar teks dan badge tidak memicu *RenderFlex overflow* pada viewport sempit.

---

## 6. Verifikasi & Pengujian

Telah teruji melalui `test/app_shell_test.dart` dan `test/widget_test.dart`:
- **Criteria #1 (No Overflow Mobile/Tablet)**: Viewport mobile (390x844) dan tablet (1024x768) menampilkan navigasi tanpa overflow.
- **Criteria #2 (State Retention)**: Rotasi layar mempertahankan tab aktif; perbesaran ukuran window dari mobile ke tablet mempertahankan isi teks formulir pelanggan.
- **Criteria #3 (Keyboard Insets)**: Simulasi keyboard `viewInsets.bottom: 280` tidak memicu overflow dan tombol submit tetap dapat dijangkau via scroll.
- **Criteria #4 (Navigation Switching)**: Berpindah antar seluruh 5 destinasi dan membuka showcase katalog dari menu pengaturan berjalan mulus.
