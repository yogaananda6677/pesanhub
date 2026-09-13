# Migrasi PostgreSQL ke MySQL

Dokumen ini adalah runbook Issue [#155](https://github.com/yogaananda6677/pesanhub/issues/155). Runtime utama memakai MySQL 8.4. Migration PostgreSQL lama dipertahankan di `pesenhub_be/migrations_postgres` sebagai histori; database MySQL baru dibangun dari baseline `pesenhub_be/migrations`.

## Keputusan kompatibilitas

- UUID disimpan sebagai `CHAR(36)` dan tetap dibuat oleh aplikasi.
- Waktu disimpan sebagai UTC `DATETIME(6)`; DSN wajib memakai `parseTime=true&loc=UTC`.
- Dokumen dan array memakai tipe `JSON` native MySQL.
- Partial unique index PostgreSQL diganti unique key yang memanfaatkan aturan multiple `NULL` MySQL. Satu payment per `(order_id, method)` menggantikan dua partial index CASH/QRIS.
- Advisory transaction lock diganti tabel `advisory_locks` dan row lock `SELECT ... FOR UPDATE`.
- Klaim worker memakai transaksi InnoDB dan `FOR UPDATE SKIP LOCKED`.
- Encoding/collation default adalah `utf8mb4/utf8mb4_0900_ai_ci`.

## Persiapan dan rehearsal

1. Bekukan perubahan schema dan catat versi aplikasi/migration PostgreSQL sumber.
2. Ambil backup PostgreSQL terverifikasi; uji restore ke environment rehearsal terisolasi.
3. Jalankan MySQL 8.4 kosong dan `./run.sh migrate-up`.
4. Ekspor tabel PostgreSQL dalam urutan dependency, transformasikan UUID, JSON/array, boolean, dan timestamp UTC, lalu impor dengan tool ETL yang terversi. Baseline schema tidak memindahkan data otomatis.
5. Bandingkan jumlah row per tabel, primary/foreign key yang orphan, total Rupiah per order/payment, distribusi status, hash payload, dan sampel alur bisnis.
6. Jalankan `./scripts/test-migrations.sh`, `./scripts/test-orders.sh`, serta smoke test API pada salinan data.

## Cutover

1. Aktifkan maintenance/read-only dan hentikan API/worker yang menulis PostgreSQL.
2. Ambil backup final dan rekam waktu cutover.
3. Salin delta data, ulang seluruh validasi reconciliation, lalu arahkan secret `DATABASE_*` ke MySQL.
4. Jalankan migration status, bootstrap API, cek `/health/live` dan `/health/ready`, lalu uji login, katalog, order, payment, outbox, dan webhook.
5. Buka traffic secara bertahap sambil memonitor error, deadlock, latency, dan backlog outbox.

## Rollback

Jika validasi gagal, hentikan writer MySQL, kembalikan konfigurasi aplikasi ke PostgreSQL yang belum dimutasi sejak cutover, deploy artifact lama, lalu validasi health dan backlog. Data baru yang sempat masuk MySQL harus direkonsiliasi eksplisit sebelum traffic dibuka kembali. Jangan menjalankan `docker compose down -v` sebagai rollback.

## Temuan selama implementasi

- CLI migration sebelumnya menutupi detail error; sekarang error penyebab ditampilkan tanpa DSN/credential.
- Placeholder PostgreSQL dapat muncul berulang dan membawa slice; adapter MySQL melakukan rebinding berdasar nomor serta ekspansi `ANY` secara aman.
- `now()` MySQL tanpa presisi dapat lebih kecil dari `DATETIME(6)` pada detik yang sama sehingga outbox tampak belum due; perbandingan due memakai `CURRENT_TIMESTAMP(6)`.
- Concurrent identity upsert dapat deadlock di InnoDB; operasi memakai retry terbatas untuk error 1205/1213.
- `RETURNING`, cast, array PostgreSQL, dan `ON CONFLICT` tidak portable; adapter SQL sementara menerjemahkan bentuk legacy yang masih dipakai, sedangkan query kompleks/locking sudah ditulis ulang secara native untuk MySQL. Penghapusan adapter dapat dilakukan bertahap setelah cutover stabil.

Semua temuan baru selama rollout harus ditambahkan ke Issue #155 beserta query/alur terdampak, dampak, reproduksi, dan status perbaikan.
