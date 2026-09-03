# Alur Cart Kasir, Catatan Bungkus, Order Review, dan Submit Manual

Dokumentasi ini menjelaskan implementasi keranjang belanja kasir (*cashier cart*), pencatatan preferensi bungkus (*takeaway*), review pesanan eksplisit, dan pengiriman pesanan manual (`CASHIER_MANUAL`) dengan jaminan idempoten untuk **Issue #28 (Phase 1B)**.

---

## 1. Arsitektur & Komponen

```
pesenhub_app/lib/
├── cart/
│   ├── models/
│   │   ├── cart_item.dart              # Model line item keranjang (kuantitas, modifier, catatan)
│   │   └── cart_order_draft.dart       # Draf pesanan lengkap (idempotency key, client order id, identitas pelanggan)
│   ├── controllers/
│   │   └── cart_controller.dart        # State management keranjang, retry handling, dan idempotency locks
│   └── widgets/
│       ├── cart_item_tile.dart         # Tile scannable item keranjang dengan stepper kuantitas (- / +)
│       ├── order_review_dialog.dart    # Dialog/Sheet review eksplisit sebelum submit pesanan
│       └── order_success_dialog.dart   # Dialog struk konfirmasi setelah pesanan berhasil dibuat
└── pos/
    └── pos_view.dart                   # UI POS terintegrasi adaptif mobile (bottom bar) & tablet (split-screen)
```

---

## 2. Kriteria Penerimaan & Solusi Teknis

### 2.1 Review Eksplisit Sebelum Submit (Kriteria #1)
- `OrderReviewDialog` menampilkan rincian komprehensif sebelum pesanan dikirim ke sistem:
  - Identitas pelanggan: Nama pelanggan (wajib) dan Nomor WhatsApp (opsional).
  - Jenis layanan: Makan di Tempat (*Dine-in*) atau Bungkus (*Takeaway*) disertai Catatan Kemasan Bungkus (misal: *"Pisah kuah & sambal"*).
  - Rincian item: Kuantitas, nama item, ringkasan modifier terpilih (level pedas, topping), catatan khusus, serta subtotal per baris item.
  - Ringkasan total pembayaran transaksi.

### 2.2 Pencegahan Duplikasi & Idempotensi (Kriteria #2)
- Setiap draf transaksi baru mengenerate pasangan kunci acak unik:
  - `idempotencyKey` (UUIDv4)
  - `clientOrderId` (UUIDv4)
- **Double-Tap Lock**: Method `submitOrder()` di `CartController` memeriksa flag `_isSubmitting`. Jika request sedang berjalan, pemanggilan berikutnya ditolak seketika (*early exit*).
- **Konsistensi Retry**: Jika terjadi kegagalan jaringan atau timeout, `_idempotencyKey` dan `_clientOrderId` **tetap dipertahankan** pada controller. Pengiriman ulang (*retry*) menggunakan kunci yang persis sama sehingga backend Postgres (`pg_advisory_xact_lock`) mendeteksi request yang identik dan tidak membuat order ganda.
- Kunci baru hanya digenerate ketika pesanan sukses dibuat atau kasir secara sadar menekan *"Kosongkan"* / *"Pesanan Baru"*.

### 2.3 Konfirmasi Diskrepansi Backend (Kriteria #3)
- Bila backend mengembalikan respon kegagalan akibat perubahan ketersediaan menu/modifier (*item unavailable*) atau perubahan harga menu di server (*price discrepancy*):
  - `CartController` mendeteksi error tersebut dan mengeset `discrepancyMessage`.
  - `OrderReviewDialog` menampilkan peringatan kuning (`AppBannerType.warning`) yang meminta kasir memeriksa kembali keranjang atau mengonfirmasi perubahan harga kepada pelanggan.

### 2.4 Tombol Submit Ramah Keyboard & Safe-State (Kriteria #4)
- Form review pesanan dan submit ditempatkan dalam `SingleChildScrollView` dengan padding insets (`viewInsets.bottom`) agar tidak pernah tertutup oleh keyboard virtual.
- Tombol submit primer dinonaktifkan (`onPressed: null`) dan menampilkan teks/indikator pemrosesan saat `_isSubmitting == true`.

### 2.5 Tata Letak Adaptif Mobile & Tablet (Kriteria #5)
- **Ponsel (< 600dp)**:
  - Tampilan vertikal satu kolom: Form pelanggan di bagian atas, diikuti katalog menu.
  - Floating sticky bottom bar menampilkan jumlah item keranjang, subtotal, dan tombol cepat *"Review Pesanan"*.
  - Mengetuk bar membuka bottom sheet keranjang untuk mengubah kuantitas atau menghapus item.
- **Tablet (>= 600dp)**:
  - Tampilan split-screen berdampingan (*side-by-side*):
    - Sisi Kiri (60% lebar layar): Katalog menu (`MenuCatalogView`) dengan pencarian cepat dan chip filter kategori.
    - Sisi Kanan (40% lebar layar): Panel keranjang aktif (`AppCard`) dengan form identitas pelanggan, switch bungkus/takeaway, daftar kartu item belanja secara langsung, dan tombol *"Review & Proses Pesanan"*.
- **State Lengkap**:
  - *Empty State*: Ilustrasi keranjang kosong yang ramah kasir.
  - *Loading State*: Indikator tombol nonaktif selama komunikasi jaringan.
  - *Success State*: `OrderSuccessDialog` bergaya struk kasir dengan opsi cetak/navigasi langsung ke antrean (`QueueDestinationView`).
  - *Error State*: Banner error merah dengan kemampuan retry otomatis.
