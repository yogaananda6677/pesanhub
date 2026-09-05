# PesenHub Standalone Design Prototype

`index.html` adalah visual contract interaktif untuk redesign aplikasi PesenHub. File ini berisi HTML, CSS, JavaScript, dan ikon SVG secara inline sehingga tidak membutuhkan React, Next.js, package manager, build step, server, CDN, atau koneksi internet.

## Menjalankan

Buka `index.html` langsung dari file manager, atau jalankan:

```bash
xdg-open design/index.html
```

URL `file://` didukung. Server lokal tidak diperlukan.

## Alur yang dapat direview

- Beranda dan ringkasan antrean.
- Pembuatan pesanan kasir, opsi pedas, keranjang, dan pembayaran demo.
- Filter antrean, detail order, dan perubahan status.
- Tampilan produksi dapur.
- Ketersediaan menu dengan feedback sukses setelah perubahan.
- Status online/offline dan modal pesanan WhatsApp.
- Menu **Lainnya** dengan contoh feedback success, info, warning, dan error.

Pada viewport mobile, navigasi bawah memprioritaskan Beranda, Kasir, Antrean, dan Dapur. Ketersediaan Menu serta Pengaturan dipindahkan ke **Lainnya** agar navigasi utama lebih tenang.

## Checklist review

- Mobile: 390 × 844.
- Tablet: 768 × 1024.
- Desktop: 1440 × 900.
- Navigasi dapat digunakan dengan keyboard dan focus ring terlihat.
- Status dan feedback selalu memakai ikon serta teks, bukan warna saja.
- Tidak ada request jaringan ketika file dibuka.
