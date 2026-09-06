# Pengelolaan Katalog End-to-End (#132)

Issue #132 menjadikan PostgreSQL sebagai sumber katalog tunggal untuk aplikasi PesenHub satu outlet. Runtime aplikasi yang memiliki konfigurasi backend tidak lagi mengisi POS atau layar Menu dari `SampleMenuData`; sampel hanya dipertahankan untuk showcase/test yang tidak dikonfigurasi.

## Alur data

1. Setelah sesi login dipulihkan, aplikasi membuka snapshot SQLite agar katalog tetap dapat dibaca saat cold start.
2. `CatalogRuntimeCoordinator` meminta `GET /api/v1/admin/catalog` memakai bearer session.
3. Snapshot backend menggantikan cache dan diterbitkan ke `MenuController` POS serta `MenuAvailabilityController` dari satu sumber yang sama.
4. Saat backend tidak dapat dijangkau, snapshot terakhir tetap tampil dengan penanda offline. Tambah, edit, dan toggle dinonaktifkan; aksi baca dan pemesanan lokal mengikuti kebijakan offline/outbox yang sudah ada.
5. Saat konektivitas pulih, coordinator memuat ulang katalog otomatis. Mutasi yang sukses juga memperbarui kedua controller dan cache SQLite.

Tidak ada pemilih owner/operator. Pengguna aplikasi adalah staf outlet tunggal yang masuk lewat sesi aplikasi. Nama role `STAFF` tetap digunakan secara internal oleh backend untuk authorization dan audit, bukan sebagai mode operasional yang dapat dipilih di UI.

## Kontrak API admin

Semua endpoint di bawah memerlukan principal `STAFF` terverifikasi dan mengembalikan envelope API standar.

| Method | Path | Fungsi |
| --- | --- | --- |
| `GET` | `/api/v1/admin/catalog` | Snapshot lengkap, termasuk entitas nonaktif/habis |
| `POST` | `/api/v1/admin/categories` | Tambah kategori |
| `PATCH` | `/api/v1/admin/categories/{id}` | Ubah kategori dengan `version` |
| `POST` | `/api/v1/admin/menus` | Tambah menu beserta modifier |
| `PATCH` | `/api/v1/admin/menus/{id}` | Ubah menu, harga, urutan, dan modifier dengan `version` |
| `PATCH` | `/api/v1/admin/menus/{id}/availability` | Ubah tersedia/habis dengan `version` |

`version` adalah optimistic concurrency guard. Versi stale menghasilkan `409 VERSION_CONFLICT`; aplikasi me-rollback perubahan optimistik, menampilkan request ID, lalu mengambil snapshot server terbaru. Create/update kategori, menu, modifier, availability, dan audit log dilakukan dalam transaksi PostgreSQL yang sama. Mutasi gagal tidak menghasilkan audit palsu.

Harga memakai integer Rupiah. Flutter hanya mengirim data menu/modifier; harga final order selalu dihitung dan divalidasi ulang oleh backend ketika order di-commit. Karena itu perubahan harga atau availability setelah keranjang dibuka tidak dapat dilewati oleh nilai dari client.

## UX pengelolaan menu

- Header menunjukkan waktu pembaruan terakhir dan status online/offline.
- Aksi utama dibatasi ke `Tambah Menu`, `Kelola Kategori`, dan `Muat Ulang`.
- Kategori dapat ditambah atau diedit (nama, urutan, aktif/nonaktif).
- Menu dapat ditambah atau diedit (kategori, SKU, nama, deskripsi, harga, urutan, grup modifier dan opsi).
- Ketersediaan tetap memakai toggle optimistik dengan indikator proses dan rollback.
- Dialog editor scrollable dan responsif pada ponsel; layout daftar berubah menjadi dua kolom pada tablet.
- Banner sukses/error dipakai untuk semua hasil mutasi dan menyertakan request ID pada konflik/kegagalan server bila tersedia.

## Cache dan migrasi

Database lokal naik ke versi 5. Kolom `menu_categories.version` ditambahkan tanpa menghapus snapshot lama. Timestamp snapshot dipakai untuk menunjukkan freshness; cache tidak pernah dianggap sebagai sumber kebenaran untuk mutasi katalog.

Backend menambah migration reversible `000020_add_catalog_category_version`. Jalankan migrasi sebelum API versi ini menerima traffic.

## Validasi

- `go test ./...` menguji service, authorization handler, contract fixture, serta seluruh regresi backend.
- `TestCatalogCRUDVersionAndAuditIntegration` berjalan ketika `TEST_DATABASE_URL` tersedia dan membuktikan CRUD, modifier, version conflict, serta atomic audit di PostgreSQL.
- `flutter test test/catalog_runtime_test.dart` menguji cache offline/reconnect, read-only offline, rollback konflik, autentikasi/version request, publikasi snapshot bersama, dan viewport mobile.
- `flutter test test/menu_availability_test.dart`, `test/backend_contract_test.dart`, dan `test/local_database_test.dart` menjaga regresi availability, kontrak provider-consumer, serta migrasi/cache lokal.
- Kontrak kanonis `contracts/backend_flutter_v1.json` berada pada `contract_version: 3`; OpenAPI lengkap berada di `docs/api/openapi.yaml`.

## Runbook singkat

1. Pastikan migration backend sudah berada pada versi 20 dan health API siap.
2. Login aplikasi, buka Menu, lalu gunakan `Muat Ulang`; status harus online dan waktu freshness berubah.
3. Tambah kategori dan menu uji, edit harga/modifier, kemudian cek item yang sama langsung muncul di tab POS.
4. Putuskan backend: katalog terakhir harus tetap terbaca dan seluruh kontrol mutasi nonaktif.
5. Sambungkan kembali backend: katalog harus refresh otomatis tanpa login ulang.
6. Jika `409` muncul, jangan retry payload lama; biarkan refresh selesai, tinjau data terbaru, lalu ulangi perubahan.
