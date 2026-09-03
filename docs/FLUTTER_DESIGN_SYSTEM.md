# PesenHub Flutter Design System

Dokumen ini mendokumentasikan spesifikasi token desain, pedoman aksesibilitas, semantik status, dan komponen antarmuka pengguna pada aplikasi mobile/tablet kasir (POS) dan dapur (KDS) PesenHub ([Issue #23](https://github.com/yogaananda6677/pesanhub/issues/23)).

---

## 1. Prinsip Desain & Ergonomi Kasir

Kasir dan koki di outlet PesenHub bekerja di lingkungan yang serba cepat, sering kali memasak sambil membungkus atau mengoperasikan kasir dengan tangan berminyak/sibuk. Oleh karena itu:
1. **Target Sentuh Minimum 48 logical pixels** (Acceptance Criteria #1): Semua elemen interaktif (`AppButton`, `AppTextField`, tombol aksi) dirancang dengan batas fisik minimal 48x48 dp untuk mengurangi *miss-tap*.
2. **Semantik Bebas Ketergantungan Warna** (Acceptance Criteria #2): Tidak pernah menyampaikan informasi status hanya lewat warna. Setiap status order, status pembayaran, dan kanal sumber selalu memiliki **label teks eksplisit** dan **ikon Material unik**.
3. **Kontras Tinggi & Skalabilitas Teks** (Acceptance Criteria #3): Teks kontras tinggi terhadap latar belakang terang (`AppColors.background: #FDFBF7`, `surface: #FFFFFF`), serta teruji tidak *overflow* pada text scale besar hingga `2.0x`.
4. **Adaptasi Mobile & Tablet** (Acceptance Criteria #4): Mendukung tata letak responsif untuk layar ponsel kasir (< 600dp) dan layar tablet KDS dapur (>= 600dp).

---

## 2. Token Desain (Design Tokens)

### 2.1 Palet Warna (`AppColors`)

| Token | Nilai Hex | Penggunaan |
|---|---|---|
| `primary` | `#C0392B` | Brand utama (Warm Red/Amber nasi goreng), tombol utama, aksen |
| `primaryContainer` | `#FDEDEC` | Latar belakang chip atau kontainer aksen terpilih |
| `secondary` | `#D97706` | Aksi sekunder, badge peringatan |
| `background` | `#FDFBF7` | Latar belakang layar aplikasi (warm light) |
| `surface` | `#FFFFFF` | Latar belakang kartu, form input, modal |
| `surfaceVariant` | `#F8FAFC` | Kontainer latar sekunder, badge netral |
| `border` | `#E2E8F0` | Garis tepi kartu, field input, divider |
| `textPrimary` | `#1E293B` | Teks utama, judul, harga |
| `textSecondary` | `#64748B` | Teks penjelas, deskripsi, helper text |
| `textMuted` | `#94A3B8` | Placeholder, teks nonaktif |

### 2.2 Semantik Status Order, Pembayaran, dan Kanal (`StatusSemantics`)

#### Status Order (Lifecycle State Machine)
| Kode Status | Label Indonesia | Ikon Material | Warna Teks & Ikon | Warna Latar |
|---|---|---|---|---|
| `PENDING` | Menunggu Konfirmasi | `hourglass_top_rounded` | `#B45309` (Amber) | `#FEF3C7` |
| `ACCEPTED` | Diterima Kasir | `check_circle_outline_rounded` | `#1D4ED8` (Biru) | `#DBEAFE` |
| `PREPARING` | Sedang Dimasak | `outdoor_grill_outlined` | `#4338CA` (Indigo) | `#E0E7FF` |
| `READY_FOR_PICKUP` | Siap Diambil | `shopping_bag_outlined` | `#15803D` (Hijau) | `#DCFCE7` |
| `COMPLETED` | Pesanan Selesai | `task_alt_rounded` | `#475569` (Slate) | `#F1F5F9` |
| `REJECTED` | Pesanan Ditolak | `cancel_outlined` | `#9F1239` (Rose) | `#FFE4E6` |
| `CANCELLED` | Pesanan Dibatalkan | `block_outlined` | `#6B7280` (Abu-abu) | `#F3F4F6` |

#### Status Pembayaran
| Kode Status | Label Indonesia | Ikon Material | Warna Teks & Ikon | Warna Latar |
|---|---|---|---|---|
| `UNPAID` | Belum Bayar | `money_off_outlined` | `#B45309` (Amber) | `#FEF3C7` |
| `PAID` | Sudah Lunas | `paid_outlined` | `#15803D` (Hijau) | `#DCFCE7` |
| `FAILED` | Pembayaran Gagal | `error_outline_rounded` | `#B91C1C` (Merah) | `#FEE2E2` |
| `EXPIRED` | Kedaluwarsa | `timer_off_outlined` | `#6B7280` (Abu-abu) | `#F3F4F6` |
| `REFUNDED` | Dikembalikan | `replay_rounded` | `#0E7490` (Teal) | `#CFFAFE` |

#### Kanal Sumber Order
| Kanal | Label Indonesia | Ikon Material | Warna Teks & Ikon | Warna Latar |
|---|---|---|---|---|
| `CASHIER_MANUAL` | Kasir Manual | `point_of_sale_rounded` | `#C2410C` (Oranye) | `#FFEDD5` |
| `CUSTOMER_WEB` | Web Customer | `language_rounded` | `#6D28D9` (Ungu) | `#EDE9FE` |
| `WHATSAPP` | WhatsApp | `chat_bubble_outline_rounded` | `#047857` (Hijau Tua) | `#D1FAE5` |

---

### 2.3 Spacing & Ukuran Interaksi (`AppSpacing`)

Menggunakan sistem grid 4px:
- `xs`: 4.0 dp
- `sm`: 8.0 dp
- `md`: 12.0 dp
- `lg`: 16.0 dp
- `xl`: 20.0 dp
- `xxl`: 24.0 dp
- `xxxl`: 32.0 dp
- `radiusSm`: 8.0 dp (input, button)
- `radiusMd`: 12.0 dp (card)
- `radiusLg`: 16.0 dp (sheet, modal)
- `minTouchTarget`: 48.0 dp (standar aksesibilitas sentuh minimum)
- `tabletBreakpoint`: 600.0 dp (pemisah mobile dan tablet)

---

## 3. Komponen Inti

### 3.1 `AppButton`
```dart
AppButton(
  label: 'Simpan Pesanan',
  icon: Icons.check_circle_outline_rounded,
  isLoading: false,
  onPressed: () {},
)
```
- Tersedia varian: `.primary`, `.secondary`, `.outlined`, `.danger`.
- Memenuhi target sentuh minimum 48px.
- Mendukung label panjang dengan pembungkusan aman `Flexible` dan `ellipsis` agar tidak pernah memicu RenderFlex overflow.

### 3.2 `AppStatusBadge`
```dart
AppStatusBadge.order('PREPARING')
AppStatusBadge.payment('PAID')
AppStatusBadge.source('CASHIER_MANUAL')
```
- Menampilkan teks label + ikon unik secara berdampingan.

### 3.3 `AppCard`
- Permukaan dengan radius 12px, batas border 1px, latar belakang putih, dan dukungan interaksi `onTap`.

### 3.4 `AppTextField`
- Enforce tinggi sentuh minimum 48px.
- Dilengkapi `label`, `hintText`, `helperText`, `errorText`, dan `prefixIcon`.

### 3.5 Feedback States (`AppFeedback`)
- `AppLoadingState`: Indikator berputar terpusat dengan teks deskriptif.
- `AppEmptyState`: Ilustrasi ikon bulat, judul ramah, pesan, dan tombol aksi opsional.
- `AppErrorState`: Ikon kesalahan, judul merah, pesan kesalahan, dan tombol "Coba Lagi" (`onRetry`).
- `AppBanner`: Banner notifikasi kontekstual (`info`, `success`, `warning`, `error`) dengan tombol tutup opsional.

### 3.6 `ResponsiveLayout`
```dart
ResponsiveLayout(
  mobile: MobileOrderListView(),
  tablet: TabletSplitOrderView(),
)
```

---

## 4. Validasi & Pengujian

Seluruh komponen telah diuji secara komprehensif melalui `test/design_system_test.dart`:
1. **Target Sentuh Minimum >= 48px**: Lulus pada tombol dan kolom input.
2. **Semantik Lengkap**: Lulus pengujian keberadaan label dan ikon untuk seluruh 7 status order, 5 status pembayaran, dan 3 sumber pesanan.
3. **Skalabilitas Teks**: Lulus pengujian font scaling 1.5x dan 2.0x tanpa exception rendering.
4. **Layout Responsif**: Lulus pada ukuran mobile (400x800) dan tablet (800x1200).
5. **State Feedback**: Lulus pada loading, empty, error (termasuk tap retry callback), dan banner (termasuk tap close callback).
