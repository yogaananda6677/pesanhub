# ADR-013: Pemilihan Local Database Engine dan Strategi Cache Flutter (#32)

**Status**: Accepted  
**Tanggal**: 2026-09-04  
**Konteks**: PesenHub Mobile & Tablet POS/KDS (Phase 1B, Issue #32)  
**Terkait**: ADR-006 (Offline Outbox Pattern), PD-006 (Storage & Sync Strategy), Invariant 11 (PII Sanitization)

---

## 1. Konteks dan Masalah

Aplikasi kasir (POS) dan dapur (KDS) PesenHub memerlukan kapabilitas penyimpanan data lokal yang tangguh untuk:
1. **Cold Start Caching**: Aplikasi dapat dimuat seketika (< 300ms) menggunakan data katalog menu, status ketersediaan, dan antrean pesanan dari penyimpanan persisten lokal saat jaringan mati atau lambat.
2. **Offline Outbox Resiliency**: Menyimpan mutasi status pesanan, aksi ketersediaan menu, dan transaksi kasir saat offline untuk disinkronkan kemudian ke backend (Issue #33).
3. **Integritas Relasional**: Struktur data POS melibatkan relasi satu-ke-banyak (*one-to-many*) antara `orders` dan `order_items`, serta `menus` dan `modifier_groups`. Integritas referensial dan transaksi atomik (*ACID transactions*) sangat krusial agar tidak terjadi *orphaned items* atau inkonsistensi kalkulasi subtotal.
4. **Keamanan Data (PII & Credentials)**: Sesuai Invariant 11, data identitas pelanggan sensitif (seperti nomor telepon) tidak boleh disimpan secara mentah (*raw plaintext*) di disk lokal. Kredensial otentikasi (JWT / refresh tokens) dan API secrets dilarang keras disimpan di database aplikasi umum.

Dua kandidat engine penyimpanan lokal utama yang dievaluasi adalah **SQLite** (melalui `sqflite` + `sqflite_common_ffi`) dan **Isar Database**.

---

## 2. Matriks Perbandingan Teknis: SQLite vs Isar

| Kriteria Evaluasi | SQLite (`sqflite` + `sqflite_common_ffi`) | Isar Database (`isar` + `isar_flutter_libs`) | Keputusan & Catatan Evaluasi |
| :--- | :--- | :--- | :--- |
| **Model Data & Relasi** | **Relasional Penuh (ACID, FK, Triggers, Indexes)**.<br>Mendukung `FOREIGN KEY ON DELETE CASCADE`, transaksi multitable, dan *composite indexes*. | **Dokumen / NoSQL Objek**.<br>Mendukung relasi objek bertingkat (*links*), namun integritas referensial relasional memerlukan manajemen manual. | **SQLite Unggul**: Skema POS/KDS sangat selaras dengan skema PostgreSQL backend PesenHub. |
| **Dukungan Headless CI & Unit Test** | **Sangat Baik** (`sqflite_common_ffi`).<br>Dapat berjalan *in-memory* (`inMemoryDatabasePath`) atau di disk pada Linux, macOS, Windows tanpa membutuhkan simulator Android/iOS atau *mock platform channels*. | **Tergantung Binary Native**.<br>Membutuhkan binari native library `.so`/`.dylib`/`.dll` yang spesifik per distro Linux dan sering gagal pada *containerized headless CI*. | **SQLite Unggul**: Menjamin 100% stabilitas unit test lokal dan CI pipeline tanpa flaky mocks. |
| **Stabilitas SDK Dart 3+ & Ekosistem** | **Sangat Stabil & Mature**.<br>Dirawat aktif oleh komunitas Flutter/Dart, dependensi stabil tanpa konflik *code generation* atau Dart SDK 3.x *macro/ffi changes*. | **Risiko Kompatibilitas Tinggi**.<br>Isar v3 mengalami isu pemeliharaan binding native pada SDK Dart modern, serta migrasi ke Isar v4 masih bersifat experimental. | **SQLite Unggul**: Memenuhi standar *enterprise-grade durability* jangka panjang. |
| **Skema Migrasi Versi** | **Native SQL Versioning** (`onUpgrade` hook).<br>Mendukung *step-by-step schema migrations* (v1 -> v2 -> v3) dengan integritas data fixture teruji. | **Skema Model Generator**.<br>Migrasi otomatis untuk penambahan field, namun penyesuaian tipe atau restrukturisasi relasi memerlukan skrip manual. | **SQLite Unggul**: Migrasi deterministik dan mudah diaudit. |
| **Performa Baca/Tulis** | **Sangat Cepat**.<br>< 1ms untuk batch query katalog (50–200 menu) dan snapshot antrean. | **Ultra Cepat**.<br>Direct C++ memory mapping, sedikit lebih cepat pada dataset raksasa (> 100k dokumen). | **Seri / Memadai**: Skala data POS/KDS per outlet adalah 100–10.000 records harian, di mana perbedaan mikrodetik tidak berdampak pada UX kasir. |
| **Penyimpanan Sensitif (PII Sanitization)** | **Terkontrol Penuh**.<br>Tiap kolom dapat disanitasi secara eksplisit pada layer repository sebelum INSERT/UPDATE. | **Terkontrol via Model Mapping**.<br>Bisa disanitasi pada model conversion. | **Seri**: Keduanya dapat menerapkan Invariant 11. |

---

## 3. Keputusan

**Dipilih: SQLite (`sqflite: ^2.4.3`, `sqflite_common_ffi: ^2.4.2+1`, `path: ^1.9.1`)**.

### Alasan Utama:
1. **Keselarasan Domain Relasional**: Entitas `queue_orders` dan `queue_order_items` memerlukan *cascade deletion* dan integritas referensial yang kuat.
2. **Kestabilan Headless & CI Pipeline**: Dengan `sqflite_common_ffi`, unit test diuji langsung menggunakan engine SQLite sungguhan (*real C engine*) secara *in-memory* tanpa mocking buatan yang rentan divergensi.
3. **Kepatuhan Dart SDK 3+**: Menghindari resiko ketergantungan Isar yang tertinggal dari rilis Flutter upstream.

---

## 4. Desain Skema Database dan Migrasi

### 4.1. Versi 1 (v1)
- `categories`: `id TEXT PRIMARY KEY, name TEXT NOT NULL, sort_order INTEGER NOT NULL, is_active INTEGER NOT NULL`
- `menus`: `id TEXT PRIMARY KEY, category_id TEXT NOT NULL, sku TEXT NOT NULL, name TEXT NOT NULL, description TEXT, price_amount INTEGER NOT NULL, is_available INTEGER NOT NULL, version INTEGER NOT NULL, sort_order INTEGER NOT NULL, is_drink INTEGER NOT NULL, modifier_groups_json TEXT`
- `queue_orders`: `id TEXT PRIMARY KEY, order_number TEXT NOT NULL, customer_name TEXT NOT NULL, customer_phone_masked TEXT NOT NULL, source TEXT NOT NULL, order_status TEXT NOT NULL, payment_status TEXT NOT NULL, is_takeaway INTEGER NOT NULL, takeaway_notes TEXT, created_at TEXT NOT NULL, version INTEGER NOT NULL`
- `queue_order_items`: `id INTEGER PRIMARY KEY AUTOINCREMENT, order_id TEXT NOT NULL, name TEXT NOT NULL, quantity INTEGER NOT NULL, unit_price INTEGER NOT NULL, notes TEXT, is_drink INTEGER NOT NULL, FOREIGN KEY (order_id) REFERENCES queue_orders (id) ON DELETE CASCADE`
- `sync_metadata`: `key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL`

### 4.2. Versi 2 (v2) - Migrasi Bertahap
- **Composite Indexes**:
  - `idx_menus_category_availability` pada `menus(category_id, is_available)` untuk mempercepat filter kategori kasir.
  - `idx_queue_orders_status_created` pada `queue_orders(order_status, created_at)` untuk mengoptimalkan tampilan KDS dan antrean aktif.
- **Tabel Tambahan**:
  - `recent_customers`: `id TEXT PRIMARY KEY, name TEXT NOT NULL, masked_phone TEXT NOT NULL, last_order_at TEXT NOT NULL` untuk *autocomplete* pelanggan kasir manual tanpa menyimpan nomor telepon mentah.
- **Jaminan Migrasi**: Seluruh data fixture v1 dipertahankan 100% tanpa kehilangan record saat eksekusi `onUpgrade(db, 1, 2)`.

---

## 5. Mekanisme Cold Start dan Stale Marker

Saat aplikasi dibuka:
1. **Fase 1 (Local Hydration)**:
   - `ColdStartCacheService` membaca data terakhir dari tabel `categories`, `menus`, dan `queue_orders`.
   - Menghitung umur cache berdasarkan `sync_metadata.catalog_last_cached_at` dan `sync_metadata.queue_last_cached_at`.
   - Menetapkan status `isStale = true` jika umur cache melebihi ambang batas (default: 15 menit) atau jika status jaringan sedang offline.
2. **Fase 2 (UI Feedback)**:
   - Menampilkan *Stale Indicator Chip* / *Banner* pada layar POS, Queue, dan KDS bertuliskan: *"Mode Offline: Menampilkan data cache (Terakhir diperbarui: HH:mm)"*.
   - Saat sinkronisasi backend berhasil, data lokal diperbarui secara atomik dalam transaksi SQLite, dan marker berubah menjadi segar (*fresh*).

---

## 6. Penanganan Data Sensitif (PII Sanitization & Credentials)

Sesuai **Invariant 11 (PII Sanitization)**:
1. **Nomor Telepon Pelanggan**: Seluruh nomor telepon pelanggan yang masuk melalui POS atau sinkronisasi API harus melewati fungsi `PiiSanitizer.maskPhone(...)` sebelum ditulis ke SQLite (misal `081234567890` -> `0812****7890`).
2. **Kredensial & Token**:
   - Token otentikasi (JWT / Refresh Tokens) **DILARANG KERAS** disimpan di SQLite.
   - Tabel `sync_metadata` hanya boleh menyimpan metadata sinkronisasi non-rahasia (`last_sync_timestamp`, `schema_version`, `device_id`).
   - Upaya menyimpan key bertema `token`, `secret`, `password`, atau `authorization` pada `sync_metadata` akan melempar `SecurityException`.

---

## 7. Strategi Fallback

Jika terjadi anomali kritis pada database lokal:
1. **Disk I/O Error / Corrupt Database File**:
   - Sistem menangkap `DatabaseException` saat pembukaan koneksi.
   - Melakukan *safe backup rename* (`pesenhub.db.corrupt.<timestamp>`) dan merekonstruksi skema bersih baru.
   - Mengambil *full snapshot* dari backend API saat jaringan tersedia.
2. **In-Memory Fallback untuk Lingkungan Read-Only / Testing**:
   - Pengujian otomatis dan mode simulasi dapat menggunakan `inMemoryDatabasePath` sehingga tidak meninggalkan jejak artefak disk dan tidak memerlukan izin penulisan filesystem khusus.

