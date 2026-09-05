# Flutter UI/UX Contract

Dokumen ini mencatat implementasi redesign Issue #121. Visual contract utamanya
adalah [`design/index.html`](../design/index.html); business logic, kontrak API,
offline outbox, dan key pengujian lama tetap dipertahankan.

## Token visual

- Primary: `#176B4D`; primary dark: `#104C38`; primary container: `#EAF6F0`.
- Background warm: `#F7F6F2`; surface: `#FFFFFF`; border: `#DCE4DF`.
- Accent operasional: orange `#E98A15`; semantic success/info/warning/error
  tetap memakai pasangan foreground dan background yang memiliki label serta ikon.
- Spacing memakai grid 4 dp, radius 10/14/18 dp, dan target sentuh minimal 48 dp.
- Card menggunakan surface putih, border tipis, dan elevation rendah agar informasi
  operasional tetap mudah dipindai.

## Hierarki navigasi

Mobile menampilkan lima akses saja pada bottom navigation:

1. Ringkasan
2. Kasir
3. Antrean
4. Dapur KDS
5. Lainnya

`Lainnya` membuka bottom sheet untuk Ketersediaan Menu dan Pengaturan. Tablet dan
desktop tetap memakai navigation rail enam destinasi agar perpindahan pada layar
besar efisien. `IndexedStack` dipertahankan supaya input dan posisi screen tidak
hilang ketika navigasi atau ukuran layar berubah.

## Feedback aksi

`AppFeedback.show` adalah pola transient global untuk success, info, warning, dan
error. Setiap feedback memiliki ikon, judul, pesan spesifik, warna foreground dan
background, tombol tutup, serta live-region screen reader. Pola ini dipakai oleh:

- tambah item serta validasi keranjang POS;
- perubahan status antrean;
- quick action tiket KDS;
- perubahan ketersediaan menu.

Konfirmasi pembuatan order tetap memakai dialog sukses karena membutuhkan pilihan
lanjutan “lihat antrean” atau “pesanan baru”. Error persisten tetap memakai
`AppBanner`/`AppErrorState` dengan retry atau tindakan koreksi.

## Review aksesibilitas dan responsif

- Semua `AppButton`, navigation destination, switch, dan tile sekunder memiliki
  target minimal 48 dp.
- Status tidak disampaikan melalui warna saja: badge dan feedback memakai teks
  serta ikon; switch memiliki label dan state semantics.
- Feedback transient diumumkan sebagai live region.
- Field tetap dapat dijangkau ketika keyboard terbuka dan konten utama scrollable.
- Komponen yang padat berubah dari row/grid menjadi wrap, stack, atau kolom pada
  layar sempit dan text scale besar.
- Test matrix mencakup `360x800`, `390x844`, `768x1024`, dan `1280x800` pada text
  scale `1.0` dan `2.0` untuk keenam screen.

## Checklist review manual

- [ ] Coba empat tab utama dan buka Menu/Pengaturan melalui Lainnya pada mobile.
- [ ] Putar perangkat setelah mengisi nama pelanggan; input harus tetap ada.
- [ ] Tambah menu, ubah status antrean/KDS, dan ubah availability; periksa feedback.
- [ ] Aktifkan TalkBack/VoiceOver; pastikan status dan feedback dibacakan lengkap.
- [ ] Buka keyboard pada form POS dan pastikan tombol review tetap dapat dijangkau.
- [ ] Ulangi pada text scale 200% dan mode offline/stale.

