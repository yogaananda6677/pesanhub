# Agent Project Memory

## PesenHub — Outlet Order Management System

Dokumen ini adalah memori kerja proyek untuk manusia dan coding agent. Baca dokumen ini bersama `PRD.md` sebelum merencanakan atau mengubah kode. Perbarui setelah setiap sesi kerja yang menghasilkan perubahan material.

> Jangan menandai pekerjaan sebagai selesai hanya karena kode sudah ditulis. Status `DONE` hanya boleh digunakan setelah acceptance criteria dan validasi phase lulus.

## 1. Project Snapshot

| Field | Current value |
| --- | --- |
| Product | PesenHub |
| Current phase | Phase 1B — Cashier Mobile & Tablet |
| Current status | IN_PROGRESS |
| MVP target | 30 hari sejak kickoff |
| Last updated | 4 September 2026 |
| Updated by | Issue #31 menu availability management implementation and validation |

## 2. Product Intent

Membangun sistem antrean order tunggal bernama PesenHub untuk outlet nasi goreng. Aplikasi Flutter dipakai sebagai POS/KDS, backend Golang mengatur proses bisnis sekaligus menyajikan Web Customer sederhana, WAHA menghubungkan WhatsApp, Hermes membantu menerima dan mengklarifikasi order pelanggan, dan Midtrans menangani pembayaran digital. Pelanggan Web Customer dapat memesan tanpa akun dengan memasukkan nama dan nomor HP.

## 3. Invariants — Jangan Dilanggar

1. Backend Golang adalah system of record.
2. Hermes tidak mengakses database atau secret integrasi secara langsung.
3. Hermes hanya bertindak melalui tool/API backend yang memiliki validasi dan audit.
4. Pelanggan harus menyetujui ringkasan sebelum draft WhatsApp menjadi order final.
5. Harga final selalu dihitung backend, bukan Flutter atau Hermes.
6. Status pembayaran Midtrans hanya berubah setelah webhook valid diproses secara idempotent.
7. Status order dan status pembayaran merupakan dua state yang berbeda.
8. Semua mutasi dari perangkat offline memakai idempotency key dan version number.
9. Pesan otomatis dapat dihentikan dan percakapan dapat diambil alih staf.
10. Perubahan status order, pembayaran, dan agent tool call penting harus dapat diaudit.
11. Web Customer tidak boleh membuka riwayat pelanggan hanya berdasarkan nama atau nomor HP tanpa verifikasi tambahan.

## 4. Confirmed Architecture Decisions

| ID | Decision | Status | Reason |
| --- | --- | --- | --- |
| ADR-001 | Flutter untuk aplikasi POS/KDS | ACCEPTED | Satu codebase mobile lintas platform |
| ADR-002 | Golang sebagai backend dan system of record | ACCEPTED | Cocok untuk REST, WebSocket, dan concurrent event handling |
| ADR-003 | WAHA sebagai gateway development/pilot dengan exit trigger menuju platform resmi | ACCEPTED — PD-007 | PR #79 di-merge; tidak mengizinkan data production sebelum #58 |
| ADR-004 | Hermes sebagai conversational order agent | ACCEPTED | Membantu ekstraksi dan klarifikasi order melalui tool terbatas |
| ADR-005 | Midtrans untuk payment gateway | ACCEPTED | Mendukung kanal pembayaran lokal dan webhook status |
| ADR-006 | SQLite untuk local offline store; package divalidasi pada #32 | ACCEPTED — PD-006 | PR #79 di-merge; model relational/transactional sesuai menu, order, queue snapshot, dan outbox |
| ADR-007 | WebSocket + REST untuk antrean | ACCEPTED | Real-time update dengan jalur recovery |
| ADR-008 | PostgreSQL 16 sebagai database backend | ACCEPTED | Diminta eksplisit untuk fondasi Backend Phase 0; memakai image Alpine dengan persistent volume |
| ADR-009 | Satu root `PRD.md` untuk Backend, Mobile, dan Web Customer | ACCEPTED | Seluruh komponen memakai aturan bisnis dan roadmap yang sama |
| ADR-010 | Dua folder utama: `pesenhub_be/` dan `pesenhub_app/` | ACCEPTED | Nama komponen konsisten; Web Customer sederhana ditempatkan di `pesenhub_be/web/` |
| ADR-012 | Stack utama dijalankan dengan Docker Compose | ACCEPTED | API dibangun multi-stage, PostgreSQL 16 Alpine dan WAHA berjalan sebagai service dalam satu network |
| ADR-011 | Web Customer tanpa akun menggunakan nama dan nomor HP | ACCEPTED | Mengurangi hambatan pelanggan saat membuat order |

## 5. Phase Tracker

| Phase | Scope | Status | Started | Completed | Evidence |
| --- | --- | --- | --- | --- | --- |
| [0 — #2](https://github.com/yogaananda6677/pesanhub/issues/2) | Project readiness | DONE | 2026-09-01 | 2026-09-03 | PR #77–#80 dan `docs/PHASE_0_CLOSING_EVIDENCE.md` |
| [1A — #3](https://github.com/yogaananda6677/pesanhub/issues/3) | Core Backend | DONE | 2026-09-03 | 2026-09-03 | PR #81–#93, #94 dan `docs/PHASE_1A_CLOSING_EVIDENCE.md` |
| [1B — #4](https://github.com/yogaananda6677/pesanhub/issues/4) | Cashier Mobile & Tablet | IN_PROGRESS | 2026-09-03 | — | Issues #23, #24, #25, #26, #27, #28, #29, #30 |
| [1C — #5](https://github.com/yogaananda6677/pesanhub/issues/5) | WhatsApp, Agent & Payment | NOT_STARTED | — | — | Menunggu domain 1A |
| [1D — #6](https://github.com/yogaananda6677/pesanhub/issues/6) | MVP Integration & Release | NOT_STARTED | — | — | Menunggu 1A–1C |
| [2 — #7](https://github.com/yogaananda6677/pesanhub/issues/7) | Food Aggregator Integration | NOT_STARTED | — | — | Menunggu MVP stabil dan kontrak resmi |
| [3 — #8](https://github.com/yogaananda6677/pesanhub/issues/8) | Production Hardening | NOT_STARTED | — | — | Menunggu hasil pilot dan target kapasitas |

Status yang diperbolehkan: `NOT_STARTED`, `IN_PROGRESS`, `BLOCKED`, `DONE`.

## Current GitHub Work

- Epic Issue: [#1](https://github.com/yogaananda6677/pesanhub/issues/1)
- Phase Issue: [#4 — Phase 1B Cashier Mobile & Tablet](https://github.com/yogaananda6677/pesanhub/issues/4)
- Child Issues: #23–#35
- Phase Roadmap: [#2](https://github.com/yogaananda6677/pesanhub/issues/2), [#3](https://github.com/yogaananda6677/pesanhub/issues/3), [#4](https://github.com/yogaananda6677/pesanhub/issues/4), [#5](https://github.com/yogaananda6677/pesanhub/issues/5), [#6](https://github.com/yogaananda6677/pesanhub/issues/6), [#7](https://github.com/yogaananda6677/pesanhub/issues/7), [#8](https://github.com/yogaananda6677/pesanhub/issues/8)
- Current Issue: [#31 — Implementasi pengelolaan menu availability pada Flutter](https://github.com/yogaananda6677/pesanhub/issues/31)
- Current Branch: `feature/31-menu-availability-management`
- Pull Request: pending
- Merged Pull Requests: [#77](https://github.com/yogaananda6677/pesanhub/pull/77), [#78](https://github.com/yogaananda6677/pesanhub/pull/78), [#79](https://github.com/yogaananda6677/pesanhub/pull/79), [#80](https://github.com/yogaananda6677/pesanhub/pull/80), [#81](https://github.com/yogaananda6677/pesanhub/pull/81), [#83](https://github.com/yogaananda6677/pesanhub/pull/83), [#84](https://github.com/yogaananda6677/pesanhub/pull/84), [#85](https://github.com/yogaananda6677/pesanhub/pull/85), [#86](https://github.com/yogaananda6677/pesanhub/pull/86), [#87](https://github.com/yogaananda6677/pesanhub/pull/87), [#88](https://github.com/yogaananda6677/pesanhub/pull/88), [#90](https://github.com/yogaananda6677/pesanhub/pull/90), [#91](https://github.com/yogaananda6677/pesanhub/pull/91), [#92](https://github.com/yogaananda6677/pesanhub/pull/92), [#93](https://github.com/yogaananda6677/pesanhub/pull/93), [#94](https://github.com/yogaananda6677/pesanhub/pull/94), [#95](https://github.com/yogaananda6677/pesanhub/pull/95), [#96](https://github.com/yogaananda6677/pesanhub/pull/96), [#97](https://github.com/yogaananda6677/pesanhub/pull/97), [#98](https://github.com/yogaananda6677/pesanhub/pull/98), [#99](https://github.com/yogaananda6677/pesanhub/pull/99), [#100](https://github.com/yogaananda6677/pesanhub/pull/100), [#101](https://github.com/yogaananda6677/pesanhub/pull/101), [#102](https://github.com/yogaananda6677/pesanhub/pull/102)
- Status: `IN_PROGRESS`
- Exit Criteria: Seluruh acceptance criteria #31 terpenuhi (toggle sukses memperbarui seluruh view via event/version, rollback & pesan actionable pada failure, role guard non-staf, item unavailable tidak dapat dipesan di POS, tata letak responsif mobile & tablet)
- Validation: `dart format`, `flutter analyze` (0 issue), `flutter test` (78/78 pass), backend check pass
- Next Step: Review/merge Issue #31, lalu lanjut ke Issue #32 (Pilih dan implementasikan local database serta cache Flutter)

## 6. Current Phase Checklist

### Phase 0 — Discovery dan Fondasi

- [x] Tetapkan nama produk: PesenHub.
- [x] Tetapkan satu PRD utama untuk seluruh komponen.
- [x] Tetapkan dua folder utama: `pesenhub_be/` dan `pesenhub_app/`.
- [x] Tempatkan Web Customer sederhana di area `pesenhub_be/web/` untuk MVP.
- [x] Konfirmasi scope satu outlet dan jumlah perangkat (PD-001/PD-002, PR #79).
- [x] Konfirmasi alur pickup/delivery dan aturan order sah (PD-003/PD-004, PR #79).
- [x] Konfirmasi kanal Midtrans serta pembayaran tunai (PD-005, PR #79).
- [x] Pilih SQLite sebagai engine local store; package divalidasi pada #32 (PD-006, PR #79).
- [x] Pilih database backend.
- [x] Buat struktur repository Backend (`pesenhub_be/`); aplikasi Flutter `pesenhub_app/` tetap tidak diubah.
- [x] Buat environment development tanpa secret di repository.
- [x] Buat kontrak API fondasi untuk health endpoint.
- [x] Buat schema/migration database awal.
- [x] Bangun dan jalankan API, PostgreSQL, dan WAHA sebagai stack Docker Compose dengan API runtime non-root.
- [ ] Uji koneksi Flutter ke REST/WebSocket Backend — dijadwalkan pada #48/#49, bukan blocker #2.
- [ ] Uji webhook WAHA dan pengiriman pesan dev — dijadwalkan pada #36–#43/#51, bukan blocker #2.
- [ ] Uji Hermes structured tool call — dijadwalkan pada #38–#41/#52, bukan blocker #2.
- [ ] Uji Midtrans sandbox dan webhook validation — dijadwalkan pada #45–#47/#53, bukan blocker #2.
- [x] Aktifkan CI, lint, unit test, dan format check sebagai required checks (PR #78).

### Phase 1A — Core Backend

- [x] #13: Tetapkan API convention, error response, pagination, dan versioning (PR #81)
- [x] #14: Desain domain model dan migration data inti (PR #83)
- [x] #15: Implementasi identifikasi dan profil pelanggan (PR #84)
- [x] #16: Implementasi menu, category, modifier, harga, dan availability (PR #85)
- [x] #17: Implementasi order creation CASHIER_MANUAL, source tracking, dan idempotency (PR #86)
- [x] #18: Implementasi lifecycle order, validasi transisi, dan audit status (PR #87)
- [x] #19: Implementasi unified order query dan filter antrean (PR #88)
- [x] #20: Implementasi WebSocket order event dan recovery (PR #91)
- [x] #21: Implementasi customer ordering web dan validasi identitas (PR #92)
- [x] #22: Implementasi audit log perubahan pesanan (PR #93)

### Phase 1B — Cashier Mobile & Tablet

- [x] #23: Bangun design system Flutter PesenHub (PR #95)
- [x] #24: Implementasi responsive app shell mobile dan tablet (PR #96)
- [x] #25: Implementasi dashboard kasir dan operational summary (PR #97)
- [x] #26: Implementasi unified order queue, source badge, dan alert visual (PR #98)
- [x] #27: Implementasi menu search, category filter, modifier, dan level kepedasan (PR #99)
- [x] #28: Implementasi cart, catatan bungkus, order review, dan submit manual (PR #100)
- [x] #29: Implementasi order detail, status timeline, dan contextual quick action (PR #101)
- [x] #30: Implementasi KDS adaptif untuk tablet dan mobile (PR #102)
- [x] #31: Implementasi pengelolaan menu availability pada Flutter (PR pending)
- [ ] #32: Pilih dan implementasikan local database serta cache Flutter
- [ ] #33: Implementasi offline outbox dan background synchronization
- [ ] #34: Implementasi conflict handling dan duplicate prevention Flutter
- [ ] #35: Implementasi network indicator, local notification, audio, dan heads-up alert

## 7. Work Completed

### 1 September 2026 — PesenHub Naming and Customer Web Scope

- Menetapkan nama produk menjadi PesenHub.
- Menetapkan satu `PRD.md` utama untuk Backend, Mobile, dan Web Customer.
- Menetapkan struktur dua folder utama: `pesenhub_be/` dan `pesenhub_app/`.
- Menambahkan Web Customer sederhana ke scope MVP di dalam area backend.
- Menentukan identitas minimum pelanggan Web Customer berupa nama dan nomor HP.
- Menambahkan sumber order `CUSTOMER_WEB`, alur publik, endpoint awal, keamanan token status, dan kebutuhan rate limit.
- Phase 0 dimulai dan berstatus `IN_PROGRESS`; belum ada kode aplikasi yang dinyatakan selesai.

### 1 September 2026 — Documentation Bootstrap

- Membuat `PRD.md` versi awal.
- Membagi implementasi menjadi Phase 0 sampai Phase 6.
- Menetapkan boundary awal Flutter, Golang, WAHA, Hermes, Midtrans, dan local store.
- Membuat `MEMORY.md` untuk pelacakan phase dan keputusan agent.
- Belum ada kode aplikasi atau integrasi yang dinyatakan selesai.

## 8. Current Blockers and Open Questions

| ID | Question / blocker | Owner | Needed by | Status |
| --- | --- | --- | --- | --- |
| Q-001 | Satu outlet atau multi-outlet sejak MVP? | Product owner | Phase 0 | RESOLVED — satu outlet, PD-001/PR #79 |
| Q-002 | Satu perangkat POS/KDS atau beberapa perangkat? | Product owner | Phase 0 | RESOLVED — satu kasir + satu KDS, PD-002/PR #79 |
| Q-003 | Pickup saja atau termasuk delivery? | Product owner | Phase 0 | RESOLVED — pickup-only, PD-003/PR #79 |
| Q-004 | Kapan order dianggap sah? | Product owner | Phase 0 | RESOLVED — konfirmasi, validasi, commit atomik, PD-004/PR #79 |
| Q-005 | Kanal pembayaran Midtrans yang diaktifkan? | Product owner | Phase 0 | RESOLVED — QRIS, PD-005/PR #79 |
| Q-006 | SQLite atau Isar? | Lead engineer | Phase 0 | RESOLVED — SQLite; package dipilih pada #32, PD-006/PR #79 |
| Q-007 | PostgreSQL sebagai database backend? | Lead engineer | Phase 0 | RESOLVED — PostgreSQL 16 |
| Q-008 | Risiko penggunaan WAHA diterima atau perlu WhatsApp Business Platform resmi? | Product owner | Phase 0 | RESOLVED — dev/pilot dengan exit trigger, PD-007/PR #79 |
| Q-009 | Web Customer mengizinkan pembayaran tunai, Midtrans, atau keduanya? | Product owner | Phase 0 | RESOLVED — cash-at-pickup + QRIS saat siap, PD-005/PR #79 |
| Q-010 | Perlukah OTP untuk membuka detail/riwayat pesanan lama? | Product owner | Phase 1A | OPEN |
| Q-011 | Akun/team mana yang menjadi Code Owner root, Backend, Mobile, workflow, dan dokumentasi? | Repository owner | Phase 0 | RESOLVED — `@yogaananda6677`, PR #78 |
| Q-012 | Kredensial signing Android dan target distribusi produksi? | Repository owner | Phase 1D | OPEN |
| Q-013 | Kosakata status order/payment canonical mana yang dipakai oleh schema, API, dan Flutter? | Product owner + lead engineer | Phase 0 | RESOLVED — PD-008/PR #79 |
| Q-014 | Bagaimana contributor memperoleh akses ke prototype desain kasir yang saat ini HTTP 401? | Product/design owner | Phase 0 | OPEN — diperlukan sebelum #23 |

## 9. Next Recommended Work

1. Selesaikan #76 dan buat Phase Closing PR untuk #2 setelah seluruh exit criteria terbukti.
2. Pertahankan struktur root dengan folder `pesenhub_be/` dan `pesenhub_app/`.
3. Mulai Phase 1A melalui child Issue #13 setelah Phase 0 ditutup.
4. Stabilkan contract/domain 1A sebelum pekerjaan Mobile 1B atau integrasi 1C yang bergantung padanya.
5. Jalankan Phase 1D hanya setelah 1A–1C memenuhi exit criteria masing-masing.
6. Jangan implementasikan adapter Phase 2 tanpa akses kontrak aggregator resmi.

## 10. Agent Session Update Template

Salin bagian ini ke bawah `Work Log` setelah satu sesi implementasi.

```md
### YYYY-MM-DD — Judul Sesi

**Goal**
- Tujuan sesi.

**Changed**
- File/fitur yang berubah.

**Decisions**
- Keputusan baru beserta alasannya.

**Validation**
- `command`: PASS/FAIL
- Skenario manual: PASS/FAIL

**Known Issues**
- Masalah yang belum selesai.

**Next**
- Langkah paling aman berikutnya.
```

## 11. Rules for Coding Agents

1. Baca `PRD.md` dan seluruh `MEMORY.md` sebelum membuat rencana.
2. Jangan memulai phase, fitur, bug, atau task tanpa GitHub Issue yang disetujui dan di-assign; percakapan, `PRD.md`, dan `MEMORY.md` bukan pengganti Issue.
3. Kerjakan setiap issue pada branch bernomor terpisah dan ajukan PR untuk review Owner serta CI; jangan direct push ke `main`.
4. Kerjakan hanya current phase kecuali pengguna secara eksplisit menyetujui phase paralel dan keputusan tersebut dicatat.
5. Jangan mengulang item berstatus `DONE` tanpa alasan regresi atau permintaan perubahan.
6. Jangan memperluas scope diam-diam; catat proposal sebagai open question.
7. Jangan menyimpan token, password, API key, session WAHA, atau Midtrans server key di repository.
8. Jangan mengubah invariants tanpa mencatat ADR baru dan persetujuan product owner.
9. Jalankan test dan pemeriksaan statis yang relevan sebelum menandai selesai.
10. Catat command validasi dan hasilnya; jangan menulis `PASS` tanpa menjalankannya.
11. Update Current GitHub Work, checklist, phase tracker, decision log, dan work log dalam perubahan yang sama.
12. Phase Issue hanya ditutup oleh Phase Closing PR setelah seluruh child issue dan exit criteria selesai.
13. Jika berhenti karena blocker, tulis kebutuhan spesifik untuk melanjutkan tanpa mengarang nomor Issue, branch, atau PR.

## 12. Decision Log Template

| ID | Date | Decision | Alternatives | Reason | Status |
| --- | --- | --- | --- | --- | --- |
| ADR-XXX | YYYY-MM-DD | Keputusan | Opsi lain | Alasan | PROPOSED/ACCEPTED/SUPERSEDED |

## 13. Work Log

Tambahkan sesi terbaru di bagian paling atas agar kondisi terkini mudah ditemukan.

### 4 September 2026 — Issue #31 Menu Availability Management

**Goal**
- Memungkinkan staf berwenang mengubah ketersediaan item menu secara cepat pada kasir mobile dan tablet PesenHub dengan umpan balik optimistik, proteksi role guard (staf aktif vs mode pantau), rollback otomatis ke state server bila terjadi kegagalan atau konflik versi (Invarian #8), sinkronisasi langsung ke katalog pemesanan POS agar item habis terkunci seketika, serta tata letak responsif pada mobile dan tablet.

**Changed**
- Mengimplementasikan `MenuAvailabilityController` di `pesenhub_app/lib/menu/controllers/menu_availability_controller.dart` dengan role guard (`STAFF`), status filtering (`ALL`, `AVAILABLE`, `UNAVAILABLE`), category filtering, search dengan debounce 250ms, in-flight action protection, optimistic toggle, version contract (`PATCH /api/v1/admin/menus/{id}/availability`), rollback otomatis saat failure, serta callback sinkronisasi POS `onAvailabilityChanged`.
- Membangun komponen UI `MenuAvailabilityCard` di `pesenhub_app/lib/menu/widgets/menu_availability_card.dart` dengan visual nama/SKU/kategori, badge status `Tersedia` (hijau) vs `Habis` (merah), chip versi `v{version}`, in-flight loading spinner, switch toggle ergonomis (>= 48px), dan penonaktifan interaksi dengan catatan otorisasi jika role bukan `STAFF`.
- Membangun antarmuka `MenuAvailabilityView` di `pesenhub_app/lib/menu/menu_availability_view.dart` dengan header role status, banner aksi/error, input pencarian, filter chip status dan kategori, grid responsif 2 kolom pada tablet (>= 600dp) serta kolom tunggal pada mobile (< 600dp), lengkap dengan loading, empty, dan error state.
- Memperbarui `MenuDestinationView` di `pesenhub_app/lib/shell/destination_views.dart` untuk menampilkan `MenuAvailabilityView` dan menyinkronkan ketersediaan menu ke katalog kasir POS.
- Memperbaiki penanganan list defensif pada `MenuController.setCatalog` di `pesenhub_app/lib/menu/controllers/menu_controller.dart`.
- Menambahkan unit dan widget tests komprehensif di `pesenhub_app/test/menu_availability_test.dart` (6 test cases menguji Criteria #1–#5) dan memastikan seluruh 78 test cases Flutter lulus.
- Menambahkan dokumentasi arsitektur di `docs/MENU_AVAILABILITY.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (78/78 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #31, lalu lanjut ke Issue #32 (Pilih dan implementasikan local database serta cache Flutter).

### 4 September 2026 — Issue #30 Adaptive Kitchen Display System (KDS) for Tablet and Mobile

**Goal**
- Menyediakan Kitchen Display System (KDS) adaptif yang mengoptimalkan alur kerja kru dapur/barista pada tablet (multi-order grid tanpa horizontal overflow) dan mobile (single-column card stack), mengurutkan tiket secara deterministik dengan prioritas tiket overdue (> 15 menit) disusul FIFO, memisahkan secara visual item makanan vs minuman barista serta menonjolkan level kepedasan dan catatan bungkus (takeaway packaging notes), dan menyediakan aksi status 1-tap (`Mulai Masak` / `Tandai Siap`) yang mematuhi kontrak versi optimistik serta mencegah double action / double tap.

**Changed**
- Mengimplementasikan `KdsController` di `pesenhub_app/lib/kds/controllers/kds_controller.dart` dengan filter status (`ALL`, `ACCEPTED`, `PREPARING`), sorting deterministik (overdue first, lalu FIFO timestamp), pencegahan double-action via `processingOrderIds`, dan aksi transisi 1-tap yang memperbarui state secara atomik.
- Membangun komponen UI `KdsTicketCard` di `pesenhub_app/lib/kds/widgets/kds_ticket_card.dart` dengan visual badge sumber dan nama/nomor order, banner merah mencolok untuk tiket overdue (> 15 menit) beserta timer durasi, kontainer catatan bungkus pesanan takeaway, pemisahan item makanan dengan kuantitas tebal & sorotan level kepedasan, seksi minuman barista terpisah dengan ikon cangkir kopi, dan tombol aksi 1-tap kontekstual.
- Membangun `KdsView` di `pesenhub_app/lib/kds/kds_view.dart` dengan filter chips status, tata letak adaptif (1 kolom pada layar mobile < 600dp, grid 2/3 kolom pada tablet >= 600dp / >= 960dp) tanpa horizontal overflow, dan penanganan state lengkap (`empty`, `loading`, `error`).
- Menghubungkan `KdsView` ke `KdsDestinationView` di `pesenhub_app/lib/shell/destination_views.dart`.
- Menambahkan unit dan widget tests komprehensif di `pesenhub_app/test/kds_test.dart` (5 test cases menguji Criteria #1–#5) dan memastikan seluruh 72 test cases Flutter lulus.
- Menambahkan dokumentasi arsitektur di `docs/ADAPTIVE_KDS.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (72/72 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #30, lalu lanjut ke Issue #31 (Implementasi pengelolaan menu availability pada Flutter).

### 4 September 2026 — Issue #29 Order Detail, Status Timeline, and Contextual Quick Actions

**Goal**
- Menampilkan detail operasional lengkap pesanan pada kasir mobile dan tablet PesenHub, memisahkan timeline status pesanan dari status pembayaran (Invarian #7), menangani konflik versi optimistik (*stale version conflict*) tanpa menimpa data server, menerapkan pembatasan hak akses (*role guard*), serta menyajikan tepat satu aksi status utama kontekstual sesuai state saat ini (misal: `PREPARING` -> *"Tandai Siap"* menuju `READY_FOR_PICKUP`).

**Changed**
- Menambahkan model `OrderAction` di `pesenhub_app/lib/order/models/order_action.dart` (`targetStatus`, `label`, `icon`, `isDestructive`, `helperText`).
- Mengimplementasikan `OrderDetailController` di `pesenhub_app/lib/order/controllers/order_detail_controller.dart` dengan role guard (`STAFF`, `KDS`, `CUSTOMER`), seleksi tepat satu `primaryAction` kontekstual, aksi sekunder, dan penanganan konkurensi versi optimistik (`VERSION_CONFLICT`) yang memuat state terbaru tanpa overwrite.
- Membangun komponen UI `OrderStatusTimeline` di `pesenhub_app/lib/order/widgets/order_status_timeline.dart` yang memvisualisasikan siklus pesanan (`Diterima` -> `Memasak` -> `Siap Diambil` -> `Selesai`) secara terpisah dari status pembayaran.
- Membangun komponen UI `OrderPaymentCard` di `pesenhub_app/lib/order/widgets/order_payment_card.dart` yang menyajikan status pembayaran independen (`UNPAID`, `PAID`, `FAILED`, `REFUNDED`) dan nilai total transaksi.
- Membangun `OrderDetailView` di `pesenhub_app/lib/order/order_detail_view.dart` dengan header nomor order dan versi, banner peringatan konflik versi dengan tombol reload, informasi pelanggan & layanan (makan di tempat vs bungkus beserta catatan kemasan), daftar item menu dengan pemisahan barista drinks, serta tombol aksi primer kontekstual dan aksi sekunder.
- Mengintegrasikan `OrderDetailView` ke dalam antrean order `OrderQueueCard` dan `QueueView` di `pesenhub_app/lib/queue/` via callback `onTap`.
- Menambahkan test suite komprehensif di `pesenhub_app/test/order_detail_test.dart` (6 test cases menguji Criteria #1–#5) dan memastikan seluruh 67 test cases Flutter lulus.
- Menambahkan dokumentasi di `docs/ORDER_DETAIL_TIMELINE_ACTIONS.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (67/67 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #29, lalu lanjut ke Issue #30 (Implementasi KDS adaptif untuk tablet dan mobile).

### 4 September 2026 — Issue #27 Menu Search, Category Filter, and Modifiers

**Goal**
- Menyediakan katalog menu interaktif untuk kasir POS/KDS PesenHub yang mendukung pencarian menu dengan debounce, filter kategori, penandaan status ketersediaan item (*unavailable/habis*), konfigurasi modifier (*level kepedasan*, *topping*, *varian manis*) sesuai batasan backend, perhitungan harga dinamis, serta validasi *required modifier* sebelum masuk ke keranjang pesanan.

**Changed**
- Menambahkan model domain menu di `pesenhub_app/lib/menu/models/`: `menu_category.dart`, `menu_option.dart`, `menu_modifier_group.dart`, `menu_item.dart`, `menu_state.dart`, dan `sample_menu_data.dart`.
- Mengimplementasikan `MenuController` di `pesenhub_app/lib/menu/controllers/menu_controller.dart` dengan debounce search 250ms, pemilihan kategori, dan kalkulasi counter item.
- Mengimplementasikan `ModifierSelectionState` di `pesenhub_app/lib/menu/controllers/modifier_selection_state.dart` dengan validasi batasan `minSelect` & `maxSelect` backend, pencegahan pemilihan opsi habis, stepper kuantitas, dan perhitungan harga dinamis.
- Membangun komponen UI scannable di `pesenhub_app/lib/menu/widgets/`: `menu_item_card.dart` (layout tahan overflow dengan harga dan tombol vertikal), `menu_category_filter.dart` (chip kategori horizontal), dan `modifier_config_dialog.dart` (dialog/bottom sheet adaptif konfigurasi modifier).
- Membangun `MenuCatalogView` di `pesenhub_app/lib/menu/menu_catalog_view.dart` dengan grid adaptif (2 kolom ponsel, 3 kolom tablet) dan dukungan state lengkap.
- Mengintegrasikan `MenuCatalogView` ke dalam `MenuDestinationView` di `pesenhub_app/lib/shell/destination_views.dart`.
- Menambahkan test suite komprehensif di `pesenhub_app/test/menu_catalog_test.dart` (7 test cases menguji Criteria #1–#5) dan memastikan seluruh 54 test cases Flutter lulus.
- Menambahkan dokumentasi di `docs/MENU_CATALOG_MODIFIERS.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (54/54 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #27, lalu lanjut ke Issue #28 (Implementasi cart, catatan bungkus, order review, dan submit manual).

### 4 September 2026 — Issue #26 Unified Order Queue, Source Badges, and Visual Alerts

**Goal**
- Menyediakan antrean order terpadu (*Unified Order Queue*) pada aplikasi kasir POS/KDS PesenHub yang menggabungkan seluruh sumber pesanan (`WHATSAPP`, `CASHIER_MANUAL`, `CUSTOMER_WEB`), menandai pesanan baru & terlambat (*late/overdue* > 15 mnt), menampilkan minuman dan catatan bungkus secara langsung pada kartu tanpa perlu membuka layar baru, serta menjamin pengurutan stabil dan deduplikasi saat konsumsi event real-time atau rekoneksi.

**Changed**
- Menambahkan model `QueueOrderItem` di `pesenhub_app/lib/queue/models/queue_order_item.dart` (`name`, `quantity`, `unitPrice`, `notes`, `isDrink`).
- Menambahkan model `QueueOrder` di `pesenhub_app/lib/queue/models/queue_order.dart` (`id`, `orderNumber`, `customerName`, `customerPhone`, `source`, `orderStatus`, `paymentStatus`, `isTakeaway`, `takeawayNotes`, `items`, `createdAt`, `version`, `isOverdue`, `drinkItems`, `foodItems`).
- Menambahkan model state `QueueState` di `pesenhub_app/lib/queue/models/queue_state.dart` (`loading`, `success`, `empty`, `error`, `isStale`, `isOffline`).
- Mengimplementasikan `QueueController` di `pesenhub_app/lib/queue/controllers/queue_controller.dart` dengan pemetaan idempoten `Map<String, QueueOrder>` untuk deduplikasi, penanganan versi event real-time, filter status & kanal, dan stable sorting (overdue first, lalu PENDING FIFO).
- Membangun `OrderQueueCard` di `pesenhub_app/lib/queue/widgets/order_queue_card.dart` dengan badge sumber 3 kanal MVP (`AppStatusBadge.source`), alert banner merah untuk pesanan terlambat, sorotan khusus minuman barista, detail catatan bungkus takeaway, dan tombol aksi kontekstual langsung.
- Membangun `QueueFilterBar` di `pesenhub_app/lib/queue/widgets/queue_filter_bar.dart` dengan status chips ber-counter, pilihan kanal sumber, dan pencarian teks.
- Mengimplementasikan `QueueView` di `pesenhub_app/lib/queue/queue_view.dart` dengan tata letak adaptif (1 kolom pada mobile, 2 kolom pada tablet) dan dukungan penuh untuk loading, empty, error, serta stale/offline banner.
- Mengintegrasikan `QueueView` ke dalam `QueueDestinationView` di `pesenhub_app/lib/shell/destination_views.dart`.
- Menambahkan test suite komprehensif di `pesenhub_app/test/queue_test.dart` (7 test cases menguji Criteria #1–#5) dan memastikan seluruh 47 test cases Flutter lulus.
- Menambahkan dokumentasi di `docs/UNIFIED_ORDER_QUEUE.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (47/47 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #26, lalu lanjut ke Issue #27 (Implementasi menu search, category filter, modifier, dan level kepedasan).

### 3 September 2026 — Issue #25 Cashier Dashboard and Operational Summary

**Goal**
- Menyediakan dashboard ringkasan operasional kasir PesenHub yang scannable, menampilkan count antrean per status, overdue alert, antrean sinkronisasi offline, penanda keusangan data (stale/offline timestamp), serta akses 1-tap ke alur utama (POS, Antrean, KDS).

**Changed**
- Menambahkan model snapshot data operasional `OperationalSummary` di `pesenhub_app/lib/dashboard/models/operational_summary.dart` (`pendingCount`, `preparingCount`, `readyCount`, `overdueCount`, `completedCount`, `pendingSyncCount`, `lastUpdatedAt`, `isStale`, `isOffline`).
- Menambahkan representasi presentation state `DashboardState` di `pesenhub_app/lib/dashboard/models/dashboard_state.dart` (`loading`, `success`, `empty`, `error`).
- Membangun komponen UI metrik scannable di `pesenhub_app/lib/dashboard/widgets/`: `metric_card.dart` (target sentuh >= 48px, kontras tinggi, alert border) dan `freshness_indicator.dart` (timestamp format HH:mm, badge offline outbox, dan warning banner).
- Mengimplementasikan `DashboardView` di `pesenhub_app/lib/dashboard/dashboard_view.dart` dengan quick action banner 1-tap, grid metrik adaptif (2 kolom mobile, 3 kolom tablet), dan dukungan state lengkap.
- Mengintegrasikan destinasi `dashboard` pada `AppDestination` dan menghubungkan `DashboardView` ke `AppShell` di `pesenhub_app/lib/shell/app_shell.dart` dengan navigasi 1-tap ke POS, Antrean, dan KDS, serta membungkus `NavigationRail` agar bebas overflow pada layar dengan tinggi terbatas.
- Menambahkan test suite komprehensif di `pesenhub_app/test/dashboard_test.dart` (7 test cases) dan memperbarui `test/app_shell_test.dart` serta `test/widget_test.dart` (40 total test cases lulus).
- Menambahkan dokumentasi di `docs/CASHIER_DASHBOARD.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (40/40 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #25, lalu lanjut ke Issue #26 (Implementasi unified order queue, source badge, dan alert visual).

### 3 September 2026 — Issue #24 Responsive App Shell Mobile and Tablet

**Goal**
- Menyediakan kerangka navigasi adaptif (App Shell) untuk aplikasi kasir (POS) dan dapur (KDS) PesenHub yang bekerja mulus pada viewport ponsel (< 600dp) dan tablet (>= 600dp), mempertahankan state saat rotasi layar atau resize, serta menangani system insets dan keyboard secara ergonomis.

**Changed**
- Menambahkan enum destinasi `AppDestination` di `pesenhub_app/lib/navigation/app_destination.dart` (`pos`, `queue`, `kds`, `menu`, `settings`).
- Membangun tampilan placeholder berstruktur di `pesenhub_app/lib/shell/destination_views.dart`: `PosDestinationView` (dengan identitas pelanggan, pemilihan menu, total, dan submit), `QueueDestinationView` (antrean order aktif), `KdsDestinationView` (tiket memasak dapur), `MenuDestinationView` (toggle ketersediaan menu), dan `SettingsDestinationView` (pengaturan outlet dan akses katalog showcase).
- Mengimplementasikan `AppShell` di `pesenhub_app/lib/shell/app_shell.dart` dengan scaffold adaptif tunggal, `NavigationBar` pada mobile (< 600dp), `NavigationRail` permanen di sisi kiri pada tablet (>= 600dp), header outlet dengan status koneksi (`Online`), serta retensi state tak terputus menggunakan `GlobalKey` dan `IndexedStack`.
- Mengonfigurasi `PesenHubApp` di `pesenhub_app/lib/main.dart` untuk memuat `AppShell`.
- Menambahkan unit dan widget tests komprehensif di `pesenhub_app/test/app_shell_test.dart` (menguji mobile navigation bar, tablet navigation rail, retensi state tab saat rotasi portrait/landscape, retensi input formulir saat window resize, simulasi keyboard insets, dan pergantian destinasi) serta memperbarui `test/widget_test.dart`.
- Menambahkan dokumentasi spesifikasi di `docs/APP_SHELL_RESPONSIVE.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (33/33 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #24, lalu lanjut ke Issue #25 (Implementasi dashboard kasir dan operational summary).

### 3 September 2026 — Issue #23 Flutter Design System

**Goal**
- Membangun fondasi visual dan interaksi yang konsisten untuk POS/KDS mobile & tablet PesenHub: token warna, tipografi, spacing, iconography, semantik status order/pembayaran (teks + ikon + warna), komponen interaktif dengan target sentuh minimal 48px, serta feedback states (loading, empty, error, banner).

**Changed**
- Menambahkan token desain di `pesenhub_app/lib/theme/`: `app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `status_semantics.dart`, dan konfigurasi Material 3 `app_theme.dart`.
- Mengimplementasikan pemetaan status order (7 status), status pembayaran (5 status), dan sumber order (3 kanal) yang menjamin setiap status selalu memiliki label teks Indonesia dan ikon unik (tidak bergantung warna saja).
- Membangun komponen UI inti di `pesenhub_app/lib/widgets/`: `app_button.dart` (target sentuh 48px, varian primary/secondary/outlined/danger, loading, disabled), `app_card.dart`, `app_status_badge.dart`, `app_text_field.dart`, `app_feedback.dart` (`AppLoadingState`, `AppEmptyState`, `AppErrorState`, `AppBanner`), dan `responsive_layout.dart` (breakpoint 600dp).
- Menambahkan katalog showcase di `pesenhub_app/lib/showcase/design_system_showcase.dart` dan mengonfigurasikannya di `pesenhub_app/lib/main.dart`.
- Menambahkan unit dan widget tests komprehensif di `pesenhub_app/test/design_system_test.dart` dan memperbarui `pesenhub_app/test/widget_test.dart`.
- Menambahkan dokumentasi di `docs/FLUTTER_DESIGN_SYSTEM.md`.

**Validation**
- `dart format --output=none --set-exit-if-changed .`: PASS.
- `flutter analyze`: PASS (0 issue found).
- `flutter test`: PASS (27/27 tests passed).
- `cd pesenhub_be && ./run.sh check`: PASS.

**Next**
- Review/merge Issue #23, lalu lanjut ke Issue #24 (Implementasi responsive app shell mobile dan tablet).

### 3 September 2026 — Phase 1A Core Backend Closing Evidence and Transition

**Goal**
- Menutup Phase Issue #3 setelah seluruh 10 child issue (#13–#22) selesai diimplementasikan, diverifikasi, dan di-merge melalui PR #81–#93.
- Mengumpulkan bukti penutupan di `docs/PHASE_1A_CLOSING_EVIDENCE.md` dan mempersiapkan transisi ke Phase 1B (Cashier Mobile & Tablet, #4).

**Changed**
- Membuat `docs/PHASE_1A_CLOSING_EVIDENCE.md` yang merangkum hasil child issues, pemenuhan acceptance criteria, repositories matrix, dan validasi operasional.
- Memperbarui `MEMORY.md`: status Phase 1A menjadi `DONE`, status Phase 1B menjadi `NOT_STARTED` (siap dimulai), dan checklist Phase 1A ditandai selesai.

**Validation**
- `cd pesenhub_be && ./run.sh check`: PASS.
- `cd pesenhub_be && ./scripts/test-migrations.sh`: PASS.
- `cd pesenhub_be && ./scripts/test-orders.sh`: PASS.
- `cd pesenhub_be && go test -race ./...`: PASS.
- `flutter test`: PASS.
- Parse `docs/api/openapi.yaml`: PASS.

**Next**
- Merge Phase Closing PR, menutup Issue #3, dan memulai child issue pertama Phase 1B (#23: Audit kesiapan UI kasir/KDS dan dependensi Flutter).

### 3 September 2026 — Issue #22 Order Mutation Audit Logging

**Goal**
- Menyediakan audit log append-only dan immutable untuk setiap mutasi penting order (`ORDER_CREATED`, `ORDER_STATUS_CHANGED`, `AUDIT_LOGS_ACCESSED`) dengan pencatatan actor, request ID, timestamp UTC, redaksi PII ketat (tanpa nomor HP utuh, token, atau secret), serta query terotorisasi yang dibatasi role dan tercatat (self-audited).

**Changed**
- Menambahkan `MaskPhone` dan `SanitizeAuditMetadata` di `internal/order/audit.go` untuk menyamarkan nomor handphone (`+62812****7890`) dan menyensor token/secret (`[REDACTED]`) sebelum disimpan di kolom `metadata_redacted`.
- Menambahkan struct `AuditLogEntry` di `internal/order/model.go`.
- Menerapkan `SanitizeAuditMetadata` pada insert audit log di `Create`, `Transition`, dan `CreateWeb` di `internal/order/store.go`.
- Menambahkan method `GetAuditLogs` di `internal/order/store.go` dan `service.go` yang mencatat event `AUDIT_LOGS_ACCESSED` secara otomatis saat log dibaca.
- Menambahkan handler `GetAuditLogs` di `internal/order/handler.go` dengan otorisasi RBAC role `STAFF` dan mendaftarkan route `GET /api/v1/orders/{id}/audit-logs` di `cmd/api/main.go`.
- Menambahkan unit tests `audit_test.go` dan integration test PostgreSQL `audit_integration_test.go` yang membuktikan atomisitas transaksi, ketepatan 1 audit per mutasi, sanitasi PII tanpa kebocoran nomor HP utuh, dan self-audited access.
- Menambahkan dokumentasi spesifikasi di `docs/ORDER_AUDIT_LOGS.md` dan memperbarui `docs/api/openapi.yaml`.

**Validation**
- `cd pesenhub_be && ./run.sh check`: PASS.
- `cd pesenhub_be && ./scripts/test-migrations.sh`: PASS.
- `cd pesenhub_be && ./scripts/test-orders.sh`: PASS.
- `cd pesenhub_be && go test -race ./...`: PASS.
- Parse `docs/api/openapi.yaml`: PASS.

**Known Issues**
- Tidak ada.

**Next**
- Review/merge Issue #22, lalu lanjutkan ke Phase 1A closing checklist dan PR penutup Phase #3.

### 3 September 2026 — Issue #21 Customer Web Ordering and Identity Validation

**Goal**
- Memungkinkan pelanggan mobile-web membuat pesanan `CUSTOMER_WEB` tanpa akun secara aman, ringan, dan responsif dengan validasi identitas, total preview dihitung backend, pencegahan double-submit, dan token pelacakan status publik tanpa mengekspos nomor HP (Invariant 11).

**Changed**
- Menambahkan migrasi `000008_add_order_public_tracking_token.up.sql` dan `.down.sql` untuk kolom `public_tracking_token` dan indeks parsial.
- Menambahkan `PublicOrderCreateInput`, `PublicOrderResponse`, `PreviewInput`, `PreviewResponse`, dan `PublicTrackingDetail` di `internal/order/model.go`.
- Menambahkan `NormalizePhone` (E.164 +628) dan `ValidateCustomerName` di `internal/order/service.go`.
- Menambahkan method `CreateWeb`, `PreviewWeb`, dan `GetByPublicToken` di `internal/order/store.go` dan `service.go`.
- Menambahkan rate limiting berbasis IP dan endpoint HTTP di `internal/order/handler.go` serta pendaftaran route di `cmd/api/main.go`.
- Mengembangkan antarmuka web mobile-first responsif di `web/index.html`, `web/style.css`, dan `web/app.js` dengan accessibility landmarks, pencegahan double-submit, dan polling status otomatis.
- Menambahkan unit tests `web_order_test.go`, `web_ui_test.go`, dan integration test PostgreSQL `web_integration_test.go`.
- Menambahkan dokumentasi arsitektur di `docs/CUSTOMER_WEB_ORDERING.md` dan memperbarui `docs/api/openapi.yaml`.

**Validation**
- `cd pesenhub_be && ./run.sh check`: PASS.
- `cd pesenhub_be && ./scripts/test-migrations.sh`: PASS.
- `cd pesenhub_be && ./scripts/test-orders.sh`: PASS.
- `cd pesenhub_be && go test -race ./...`: PASS.
- Parse `docs/api/openapi.yaml`: PASS.

**Known Issues**
- Tidak ada.

**Next**
- Review/merge Issue #21, lalu lanjutkan ke #22 (issue terakhir Phase 1A).

### 3 September 2026 — Issue #20 WebSocket Order Events and Recovery

**Goal**
- Mendistribusikan perubahan antrean order secara real-time ke client POS/KDS melalui WebSocket dengan autentikasi (role `STAFF` & `KDS`), heartbeat ping-pong, ordering berbasis version, outbox processing, dan snapshot recovery REST saat terjadi gap / disconnect.

**Changed**
- Menambah package `internal/ws` untuk upgrade RFC 6455 tanpa external dependency, ping/pong heartbeat, thread-safe frame reading/writing, dan `Hub` untuk role-aware broadcast serta backpressure handling.
- Menambah `OutboxPublisher` di `internal/order/publisher.go` untuk membaca transactional outbox events (`ORDER_CREATED`, `ORDER_STATUS_CHANGED`), membungkus dalam `OrderEventEnvelope`, meredaksi PII untuk role `KDS`, dan mem-broadcast ke `Hub`.
- Menghubungkan `order.Store` ke `OutboxPublisher` agar commit mutasi order langsung memicu pengiriman event instan.
- Menambah endpoint WebSocket `GET /api/v1/ws/orders` di `internal/order/handler.go` dan `cmd/api/main.go`.
- Menambah unit test `internal/ws/ws_test.go`, `internal/order/publisher_test.go`, dan integration test end-to-end `internal/order/ws_integration_test.go`.
- Menambah dokumentasi arsitektur di `docs/ORDER_EVENTS_WS.md` dan memperbarui kontrak OpenAPI di `docs/api/openapi.yaml`.

**Validation**
- `cd pesenhub_be && ./run.sh check`: PASS.
- `cd pesenhub_be && ./scripts/test-migrations.sh`: PASS.
- `cd pesenhub_be && ./scripts/test-orders.sh`: PASS.
- `cd pesenhub_be && go test -race ./...`: PASS.
- Parse `docs/api/openapi.yaml`: PASS.

**Known Issues**
- Principal staff/KDS produksi masih menunggu middleware autentikasi pada issue terkait; endpoint sengaja default-deny.

**Next**
- Review/merge Issue #20, lalu lanjutkan ke #21.

### 3 September 2026 — Issue #19 Unified Order Query and Queue Filter

**Goal**
- Menyediakan read model antrean tunggal yang cepat untuk seluruh sumber dan status dengan keyset cursor pagination, filter dinamis, dan RBAC PII redaction.

**Changed**
- Menambah endpoint `GET /api/v1/orders`, `GET /api/v1/orders/queue`, dan `GET /api/v1/orders/{id}`.
- Menambah composite index `(source, status, created_at, id)`, `(created_at, id)`, dan `order_item_modifiers(order_item_id)`.
- Menambah keyset cursor pagination `(created_at, id)` deterministik tanpa duplicate record antarhalaman.
- Menambah RBAC: role `STAFF` mengakses data penuh, sedangkan role `KDS` menerima payload dengan `customer_phone` dan `customer_id` diredaksi.
- Menambah kategori item (`Makanan`/`Minuman`) dan catatan bungkus/pesanan untuk kebutuhan stasiun dapur/KDS.
- Menambah kontrak OpenAPI, dokumentasi query di `docs/ORDER_QUERIES.md`, unit tests, dan integration tests PostgreSQL.

**Validation**
- `cd pesenhub_be && ./run.sh check`: PASS.
- `cd pesenhub_be && ./scripts/test-migrations.sh`: PASS.
- `cd pesenhub_be && ./scripts/test-orders.sh`: PASS.
- `cd pesenhub_be && go test -race ./...`: PASS.
- Parse `docs/api/openapi.yaml`: PASS.

**Known Issues**
- Principal staff/KDS produksi masih menunggu middleware autentikasi pada issue terkait; endpoint sengaja default-deny.

**Next**
- Review/merge Issue #19, lalu lanjutkan ke #20.

### 3 September 2026 — Issue #18 Order Lifecycle

**Goal**
- Menjamin hanya transisi status legal yang dapat diterapkan dengan optimistic concurrency, audit, dan event atomik.

**Changed**
- Menambah state machine eksplisit dan endpoint staff `POST /api/v1/orders/{id}/status-transitions`.
- Menambah idempotency key/request hash pada status history untuk replay identik yang tidak menggandakan history, audit, atau outbox.
- Menambah optimistic version check, actor-scoped replay, reason code, serta safe errors untuk stale version, illegal transition, dan terminal state.
- Menambah kontrak OpenAPI, panduan lifecycle, unit test table-driven, dan integration test PostgreSQL concurrent retry.

**Validation**
- `go test ./...`, `go vet ./...`, dan `go test -race ./...`: PASS.
- `scripts/test-migrations.sh` dan `scripts/test-orders.sh`: PASS.
- Parse `docs/api/openapi.yaml`: PASS.

**Known Issues**
- Principal staff produksi masih menunggu middleware autentikasi pada issue terkait; endpoint sengaja default-deny.

**Next**
- Review/merge Issue #18, lalu lanjutkan unified order query pada #19.

### 3 September 2026 — Issue #17 Manual Cashier Order

**Goal**
- Membuat order `CASHIER_MANUAL` yang atomik, dihitung backend, dan aman terhadap retry bersamaan.

**Changed**
- Menambah endpoint staff `POST /api/v1/orders`, kontrak OpenAPI, serta panduan operasi.
- Menambah request hash dan client order ID, snapshot item/modifier, status history awal, audit log, dan outbox dalam satu transaksi.
- Menambah advisory transaction lock per source/idempotency key dan integration test PostgreSQL untuk concurrent replay, payload conflict, serta unavailable catalog.

**Validation**
- `go test ./...`, `go vet ./...`, dan `go test -race ./...`: PASS.
- `scripts/test-migrations.sh` dan `scripts/test-orders.sh`: PASS.
- Parse `docs/api/openapi.yaml`: PASS.

**Known Issues**
- Principal staff produksi masih menunggu middleware autentikasi pada issue terkait; endpoint sengaja default-deny.

**Next**
- Review/merge Issue #17, lalu lanjutkan lifecycle order pada #18.

### 3 September 2026 — Issue #16 Menu Catalog

**Goal**
- Menyediakan katalog category/menu/modifier group/option sebagai sumber harga integer dan availability seluruh channel.

**Changed**
- Menambah migration reversible `000004` untuk modifier group/option, stable menu sort, dan snapshot option reference.
- Menambah catalog model/service/store/handler untuk admin category/menu/availability dan public/agent read dengan filter category serta stable ordering.
- Menambah server-side price/modifier validator yang menolak menu/option unavailable, foreign/duplicate option, dan min/max ilegal dengan safe field path.
- Menambah OpenAPI dan `docs/MENU_CATALOG.md`; tabel flat lama dipertahankan untuk migration compatibility.

**Validation**
- Go format/unit/vet, handler contract, OpenAPI parse, shell syntax, dan `git diff --check`: PASS.
- PostgreSQL 16 migration/rollback/reapply, CRUD fixture, availability visibility, modifier bounds, serta seluruh fixture migration lama: PASS.

**Known Issues**
- Admin write runtime default `FORBIDDEN` sampai auth middleware memasukkan verified `STAFF` principal.
- Promo kompleks dan inventory di luar #16; order snapshot/atomic calculation dilanjutkan #17.

**Next**
- Review dan merge PR #86; setelah itu lanjut #17 untuk order creation manual, source tracking, dan idempotency.

### 3 September 2026 — Issue #15 Customer Identity and Profile

**Goal**
- Mengidentifikasi customer melalui nomor Indonesia ternormalisasi serta menyediakan create/update/history yang collision-safe dan authorization-first.

**Changed**
- Menambah normalizer `08…`/`628…`/`+628…`/`8…` ke E.164, customer service/store/handler, UUID internal, expected version, dan principal authorization.
- Menambah migration reversible `000003` untuk preferences object, optimistic version, dan create idempotency key.
- Menambah OpenAPI customer create/update/history dan `docs/CUSTOMER_IDENTITY.md` untuk collision, shared/recycled phone, privacy, dan default-deny behavior.
- Menambah unit/contract test serta memperluas migration test dengan rollback/reapply dan concurrent unique collision.

**Validation**
- Go format/unit/vet, OpenAPI parse, shell syntax, dan `git diff --check`: PASS.
- PostgreSQL 16 migration up/down/up, customer extension rollback, dan concurrent phone collision: PASS.

**Known Issues**
- Auth/OTP production tidak termasuk #15. Update/history runtime aman dengan default `UNAUTHENTICATED` sampai middleware memasukkan verified principal.
- Tidak ada auto-merge customer; collision memerlukan resolusi staf eksplisit pada issue lanjutan.

**Next**
- Review dan merge PR #85; setelah itu lanjut #16 untuk menu/category/modifier/availability.

### 3 September 2026 — Issue #14 Core Domain Schema

**Goal**
- Menyediakan model customer, menu, order snapshot, payment, history, audit, dan outbox dengan constraint aman pada PostgreSQL 16.

**Changed**
- Menambah migration reversible `000002_create_core_domain` tanpa mengubah migration terpakai `000001`.
- Menambah ERD/data invariants pada `docs/CORE_DOMAIN_MODEL.md` dan canonical enum mapping pada `internal/domain`.
- Menambah test migration container terisolasi untuk siklus up/down/up, insert sukses, duplicate idempotency, invalid status, rollback scope, dan multiple null channel reference.

**Validation**
- Domain unit test, Go format, shell syntax, dan `git diff --check`: PASS.
- PostgreSQL 16 migration up/down/up serta positive/negative constraint checks: PASS.

**Known Issues**
- Repository transaction untuk insert atomik order/items/history/audit/outbox menjadi scope #17/#22; migration hanya menyediakan constraint dan relational boundary.
- Tidak ada data production atau credential nyata yang digunakan.

**Next**
- Review dan merge PR #84; setelah itu lanjut #15 untuk identifikasi/profil pelanggan.

### 3 September 2026 — Issue #13 HTTP API Conventions

**Goal**
- Mengunci kontrak HTTP bersama sebelum endpoint domain Phase 1A dikembangkan.

**Changed**
- Menambah `docs/API_CONVENTIONS.md` dan OpenAPI 3.1 machine-readable untuk versioning, response, error, pagination, filter/sort, mutation, idempotency, version conflict, dan status code.
- Menambah package `internal/httpapi` untuk JSON/error envelope aman dan parser cursor pagination dengan default 20/maksimum 100 serta sort allowlist.
- Memvalidasi/menghasilkan `X-Request-ID` pada middleware dan mengubah panic recovery ke error envelope canonical.
- Menambah unit/contract tests untuk success primitive, validation error, invalid pagination, request ID, dan panic redaction.

**Validation**
- `gofmt`, `pesenhub_be/run.sh check`, race test, `go vet`, dan parse OpenAPI YAML: PASS.
- Integration persistence tidak relevan karena issue ini tidak mengubah database atau endpoint domain.
- Flutter tidak terdampak; contract menjadi input untuk #48/#49.

**Known Issues**
- `/api/v1/examples` pada OpenAPI hanya contoh kontrak dan bukan route runtime; endpoint domain ditambahkan oleh issue pemiliknya.

**Next**
- Review dan merge PR #83; setelah itu lanjut #14 untuk domain model dan migration inti.

### 3 September 2026 — Phase 0 Closing Audit

**Goal**
- Menutup Phase Issue #2 hanya berdasarkan child issue, repository governance, dokumentasi, dan validasi yang dapat diaudit.

**Changed**
- Menambah `docs/PHASE_0_CLOSING_EVIDENCE.md` dengan matriks acceptance criteria, hasil test, deferral, risiko, dan deviasi approval.
- Menandai Phase 0 `DONE` efektif hanya ketika Phase Closing PR di-merge dan Issue #2 ditutup.
- Memetakan spike integrasi lama ke child issue Phase 1B–1D tanpa menghapus requirement.

**Validation**
- Seluruh child issue #9–#12, #75, dan #76 `CLOSED`; tidak ada PR terbuka sebelum closing branch dibuat.
- Backend check, Docker Compose config, Flutter format/analyze/test, required checks, dan latest `main` CI/CD: PASS.

**Known Issues**
- Required approval count diubah Owner menjadi nol untuk self-merge; deviasi dari teks awal #2 dicatat eksplisit dan tidak diklaim sebagai independent review.
- Akses prototype desain Q-014 tetap dibutuhkan sebelum #23, tetapi bukan blocker Project Readiness #2.

**Next**
- Merge Phase Closing PR #81 untuk menutup #2, kemudian mulai Phase 1A dari #13.

### 3 September 2026 — Issue #76 Roadmap Synchronization

**Goal**
- Menjadikan Epic #1 dan Phase Issue #2–#8 sebagai roadmap eksekusi tanpa menghilangkan requirement PRD lama.

**Changed**
- Memetakan Phase lama 0–6 ke Phase GitHub 0, 1A, 1B, 1C, 1D, 2, dan 3 pada PRD.
- Memperbarui deliverable serta exit criteria tiap phase baru berdasarkan Phase Issue terkait.
- Memperbarui phase tracker, Current GitHub Work, next work, decision status, open question, dan checklist setelah PR #78/#79 merged.
- Menambahkan navigasi roadmap pada README; tidak ada source aplikasi, schema, API, secret, atau deployment yang diubah.

**Validation**
- Metadata Epic #1 dan Phase Issue #2–#8 diverifikasi melalui GitHub CLI.
- Konsistensi tujuh phase, link, istilah stale, dan scope dokumentasi lulus lokal; CI menunggu pada PR #80.

**Known Issues**
- Phase 0 tetap `IN_PROGRESS`; Issue #76 bukan Phase Closing PR dan tidak menutup #2.
- Prototype desain untuk #23 masih memerlukan akses Owner/Design Owner (Q-014).

**Next**
- Review dan merge PR #80, lalu buat Phase Closing PR #2 hanya setelah seluruh child issue dan exit criteria terverifikasi.

### 3 September 2026 — Issue #75 Phase 0 Product Decision Proposal

**Goal**
- Menyediakan baseline eksplisit untuk scope outlet/perangkat, fulfillment, order validity, payment, local database, risiko WAHA, serta status canonical.

**Changed**
- Menambah `docs/PHASE_0_PRODUCT_DECISIONS.md` dengan PD-001–PD-008 berstatus `EFFECTIVE_ON_MERGE`.
- Merekomendasikan single outlet, satu kasir + satu KDS (target uji maksimal tiga perangkat staf), pickup-only, cash + Midtrans QRIS, SQLite, dan penggunaan WAHA terbatas untuk development/pilot.
- Menetapkan proposal status order/payment/source canonical serta mapping istilah lama tanpa mengubah schema atau source aplikasi.
- Menautkan proposal dari PRD; sinkronisasi penuh tetap menjadi scope #76 setelah Owner menyetujui keputusan.

**Validation**
- `git diff --check`, kelengkapan Q/PD, dan pembatasan path dokumentasi lulus lokal.
- Backend/Mobile source, `.env`, Docker, migration, dan deployment tidak diubah.

**Known Issues**
- Seluruh keputusan belum efektif sebelum PR direview dan di-merge Owner.
- Detail operasional outlet dapat mengubah rekomendasi; perubahan wajib dicatat pada review PR, bukan diasumsikan.

**Next**
- Review dan merge PR #79 sebagai Owner; setelah merge, kerjakan #76 untuk menyelaraskan PRD/MEMORY dan dependency roadmap.

### 3 September 2026 — Issues #10–#12 Repository Governance

**Goal**
- Menggabungkan tiga Issue Phase 0 yang saling terkait atas persetujuan Owner: branch protection, CODEOWNERS, serta dokumentasi environment dan secret.

**Changed**
- Mengaktifkan protection `main` dengan strict required checks, satu approval, Code Owner review, stale/last-push approval, conversation resolution, admin enforcement, linear history, serta larangan force-push/deletion.
- Menonaktifkan merge commit dan rebase merge; hanya squash merge tersedia dan branch dihapus otomatis setelah merge.
- Mengaktifkan `.github/CODEOWNERS` untuk akun repository Owner `@yogaananda6677` dan mencatat kebutuhan reviewer kedua.
- Membuat `docs/ENVIRONMENT.md` berisi prasyarat, setup, environment/secret matrix, ownership, provision, rotasi, sandbox, verifikasi, dan troubleshooting aman.
- Memperbarui Contribution Policy untuk multi-issue PR yang memerlukan label Owner `policy:multi-issue-approved` serta memvalidasi semua closing Issue.
- Memperbarui panduan kontribusi, PR template, README, dan setup GitHub agar sesuai state aktual.

**Validation**
- GitHub branch protection, repository merge settings, dan label multi-issue: PASS melalui REST/CLI read-only verification.
- Parse 10 file YAML, syntax JavaScript Contribution Policy, CODEOWNERS, documentation contract, dan `git diff --check`: PASS.
- Secret-file tracking: PASS — tidak ada `.env`, `local.properties`, keystore, atau JKS tracked.
- `pesenhub_be/run.sh check` dan `docker compose config --quiet`: PASS setelah retry di luar sandbox untuk izin loopback `httptest`; checksum `.env` tidak berubah.
- Flutter `pub get`, format check, analyze, dan test: PASS; hanya ada informasi tujuh transitive dependency dengan versi baru di luar constraint.
- Contribution Policy, Backend Quality, dan Mobile Quality pada multi-issue PR #78: PASS.

**Known Issues**
- Hanya satu akun Owner yang diketahui. Approval dan Code Owner review membutuhkan collaborator kedua; author tidak boleh self-review.
- #75 dan #76 tetap terbuka dan tidak termasuk dalam PR ini.

**Next**
- Buka multi-issue PR untuk #10, #11, dan #12, tambahkan label approval Owner, tunggu seluruh CI serta review dari akun lain, lalu squash merge.

### 3 September 2026 — Issue #9 Phase 0 Readiness Audit

**Goal**
- Menghasilkan inventaris terverifikasi atas blocker Phase 0 tanpa mengubah source aplikasi, runtime, atau pengaturan GitHub yang memerlukan keputusan Owner.

**Changed**
- Membuat `docs/PHASE_0_READINESS_AUDIT.md` berisi evidence repository/GitHub, owner, status, pekerjaan yang tidak diulang, dan urutan penyelesaian.
- Mengganti placeholder Current GitHub Work dengan Epic #1, Phase Issue #2, Issue #9, branch aktif, serta blocker nyata.
- Membuat follow-up #75 untuk keputusan bisnis/integrasi Phase 0 dan #76 untuk sinkronisasi roadmap lokal dengan milestone GitHub.
- Memperbarui Q-011 dan menambah Q-013/Q-014 berdasarkan evidence audit.

**Validation**
- Git root, remote `origin`, default branch `main`, dan clean state sebelum branch dibuat: PASS.
- Backend CI, Mobile CI, Backend CD, dan Mobile CD push run terakhir: PASS.
- Branch protection/ruleset: FAIL expected — belum aktif dan ditangani #10.
- CODEOWNERS aktif: FAIL expected — belum tersedia dan ditangani #11.
- Secret tracking: PASS — hanya `.env.example` yang tracked; tidak ada nilai `.env` dibaca atau diubah.
- `git diff --check`: PASS.
- Contribution Policy, Backend Quality, dan Mobile Quality pada Pull Request #77: PASS.

**Known Issues**
- #10, #11, #12, #75, dan #76 tetap terbuka; Phase 0 belum memenuhi exit criteria.
- Prototype desain kasir merespons HTTP 401 sehingga detail visual belum dapat diverifikasi.

**Next**
- Buka PR untuk #9, tunggu seluruh required checks dan review Owner, lalu squash merge sebelum mengerjakan child issue berikutnya.

### 1 September 2026 — Mandatory Phase and Feature Workflow

**Goal**
- Menjadikan Issue → Branch → Implementasi → Pull Request → Review Owner → CI → Merge sebagai aturan wajib untuk setiap phase dan fitur.

**Changed**
- Menambah template `phase.yml` dengan scope, impact, child issue, exit criteria, bukti validasi, Definition of Done, dan checklist penutupan phase.
- Memperluas Feature Issue agar wajib memiliki Parent Phase, scope/non-scope, dampak API/database/UI/security, test scenario, dan Definition of Done.
- Memperbarui panduan kontribusi dan PR template untuk hierarki Phase Issue → child issue → Phase Closing PR serta larangan long-lived phase branch.
- Memperketat Contribution Policy: menerima branch `phase/`, menyamakan nomor branch dengan issue utama, membatasi satu closing issue, memvalidasi Parent Phase untuk Feature PR, dan mencegah Phase Issue ditutup selain oleh Phase Closing PR.
- Menambah bagian Current GitHub Work menggunakan `NOT_CREATED`; tidak ada nomor Issue, branch, atau PR aktual yang dikarang.

**Validation**
- Parse seluruh 10 file YAML `.github`: PASS.
- Kontrak field Phase Issue, Feature Issue, dan Pull Request template: PASS.
- Skenario regex branch serta kecocokan nomor branch–issue utama: PASS.
- Syntax JavaScript `Contribution Policy` dalam wrapper async GitHub Script: PASS.
- Placeholder Current GitHub Work seluruhnya `NOT_CREATED` dan pemeriksaan nomor Issue/PR palsu: PASS.
- `actionlint`: NOT_RUN — binary tidak tersedia dan tidak diinstal.

**Known Issues**
- Remote GitHub dan username/team Owner belum tersedia; Phase Issue, child issue, branch implementasi, PR, dan branch protection belum dapat dibuat.

**Next**
- Setelah remote tersedia, buat Phase Issue Phase 0 terlebih dahulu, pecah sisa exit criteria menjadi child issue, lalu minta persetujuan Owner sebelum implementasi berikutnya.

### 1 September 2026 — Monorepo Git and CI/CD Foundation

**Goal**
- Menuntaskan fondasi repository Git monorepo, memisahkan pipeline Backend dan Mobile, serta menetapkan alur kontribusi Issue → Branch → PR → Review tanpa mengubah fitur bisnis atau state Docker.

**Changed**
- Mengonfirmasi `.git/` root lama kosong, menghapus direktori kosong tersebut, lalu menginisialisasi satu repository Git valid pada root dengan branch `main`; tidak ada nested repository.
- Menambah `CONTRIBUTING.md`, template Pull Request, tiga form Issue, konfigurasi Issue, dan `CODEOWNERS.example` yang aman karena username/team GitHub belum diketahui.
- Menambah workflow `Contribution Policy` untuk memvalidasi nama branch dan referensi Issue lokal pada Pull Request ke `main`.
- Menambah CI Backend dan Mobile terpisah dengan path filter tetapi status check stabil; Backend menjalankan verify/format/vet/test serta validasi/build Compose, sedangkan Mobile menjalankan pub get/format/analyze/test/build APK debug.
- Menambah CD Backend untuk image GHCR pada `main` atau tag `backend-v*`, serta CD Mobile untuk APK release unsigned sebagai artifact 14 hari pada `main` atau tag `mobile-v*`; deployment produksi dan signing tidak ditebak.
- Menambah `docs/GITHUB_SETUP.md` dan memperbarui root `README.md` untuk branch protection, required checks, CODEOWNERS, secret masa depan, dan alur kontribusi.
- Menyelaraskan major version GitHub Actions dengan dokumentasi resmi yang berlaku pada sesi ini.

**Validation**
- Repository root, branch `main`, dan tepat satu direktori `.git`: PASS; belum ada commit atau remote dan keduanya sengaja tidak dibuat tanpa tujuan remote/Issue yang nyata.
- Parse seluruh sembilan file YAML dengan PyYAML: PASS.
- `actionlint`: NOT_RUN — binary tidak tersedia dan tidak diinstal.
- `pesenhub_be/run.sh check` dan `docker compose config --quiet`: PASS; checksum `pesenhub_be/.env` tetap `4e9f172047c7cc9f8ca11c8e7db683d4800b62676d41aff6c16b71b388821618`.
- `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, dan `flutter test`: PASS; hanya ada informasi tujuh dependency transitive dengan versi lebih baru yang tidak kompatibel dengan constraint saat ini.
- Percobaan awal inisialisasi Git di sandbox gagal karena pembatasan filesystem; retry dengan izin yang disetujui berhasil. Tidak ada container dihentikan, volume dihapus, atau `.env` diubah.

**Known Issues**
- Remote GitHub belum diketahui, sehingga push pertama, eksekusi workflow, dan branch protection belum dapat dilakukan.
- Required checks yang harus dipilih setelah workflow pertama berjalan: `Contribution Policy`, `Backend Quality`, dan `Mobile Quality`.
- `CODEOWNERS.example` harus diisi username/team nyata lalu diubah menjadi `.github/CODEOWNERS`; file aktif sengaja belum dibuat agar tidak berisi owner palsu.
- APK release masih unsigned; secret signing dan target Play Store belum ditentukan.
- Phase 0 tetap `IN_PROGRESS` karena blocker bisnis dan spike integrasi lain masih terbuka.

**Next**
- Buat repository GitHub/remote, lakukan initial commit melalui Issue dan branch yang sesuai, push, lalu aktifkan aturan pada `docs/GITHUB_SETUP.md` setelah workflow pertama menghasilkan status checks.
- Isi owner nyata untuk CODEOWNERS dan tentukan signing Android saat memasuki fase release produksi.

### 1 September 2026 — Backend Operational Guide and Automation

**Goal**
- Menyediakan satu panduan operasional dan satu script idempotent untuk setup, build, lifecycle, health, test, serta migration Backend tanpa mengubah fitur bisnis.

**Changed**
- Membuat `pesenhub_be/ATURAN.md` sebagai panduan utama berbahasa Indonesia untuk arsitektur, prasyarat, setup, command harian, keamanan, development, dan troubleshooting.
- Membuat executable `pesenhub_be/run.sh` dengan subcommand `help`, `setup`, `dev`, `start`, `build`, `rebuild`, `stop`, `down`, `restart`, `status`, `logs`, `health`, `test`, `check`, `fmt`, `migrate-up`, `migrate-down`, `migrate-status`, dan `version`.
- Menjadikan `pesenhub_be/Makefile` wrapper tipis ke `run.sh` agar tidak ada recursion atau duplikasi logika.
- Menambah mode read-only `status` pada `pesenhub_be/cmd/migrate/main.go` agar status migration dapat diperiksa memakai tool yang sama.
- Memperbarui `pesenhub_be/README.md` dan `REQUIREMENTS.md`; membuat root `README.md` dengan quick start berbasis `run.sh`.
- Membuat root `.gitignore` untuk `.env`, session/QR WAHA, log, dan artefak lokal Backend.

**Validation**
- `chmod +x pesenhub_be/run.sh`: PASS — mode aktual 775/executable.
- `bash -n pesenhub_be/run.sh`: PASS.
- `shellcheck pesenhub_be/run.sh`: NOT_RUN — `shellcheck` tidak tersedia dan tidak diinstal.
- `./run.sh`, `./run.sh help`, dan `./run.sh --help`: implementasi setara; `./run.sh help` dijalankan PASS.
- `./run.sh version`: PASS — Go/image/Docker/Compose tampil tanpa secret.
- `./run.sh setup`: PASS — Compose valid dan `.env` yang ada tidak ditimpa.
- Checksum `.env` sebelum/sesudah setup dan lifecycle: PASS — tetap `8ac9dcd655290421541b77ca71a79f311c4b236a8834ecebcf65d3d92e8dbfe7`.
- `./run.sh build`: PASS — image `pesenhub-api:dev` dibangun dan ukuran aktual `10,329,830` byte.
- `./run.sh test`: PASS — seluruh unit test Go lulus.
- `./run.sh check`: PASS — `go mod verify`, format check non-mutating, `go vet`, `go test`, dan Compose config lulus.
- Input salah `restart unknown-service`, `logs unknown-service`, dan `unknown-command`: PASS — seluruhnya ditolak dengan pesan jelas dan exit code 1.
- `./run.sh migrate-down` non-interaktif tanpa `--yes`: PASS — ditolak aman dengan exit code 1.
- `./run.sh migrate-status`: PASS sebelum dan sesudah lifecycle — `version=1 dirty=false`, tanpa mutasi database.
- Lifecycle `stop → start → health → down → dev → health`: PASS.
- `./run.sh restart api`: PASS — service spesifik tervalidasi dan kembali healthy.
- Identitas volume sebelum/sesudah lifecycle: PASS — tetap `pesenhub_postgres_data`, dibuat `2026-09-01T13:50:37+07:00`; tidak ada flag `-v` atau penghapusan volume.
- Status akhir: PASS — API healthy, PostgreSQL healthy pada host port 55432, WAHA container healthy pada port 3000.
- Health akhir: PASS — live HTTP 200; ready HTTP 200 `degraded`, database `up`, WAHA `down` hanya karena session `default` belum dibuat.

**Known Issues**
- Root `.git/` masih kosong/bukan repository valid, sehingga executable bit dan file baru tidak dapat diverifikasi sebagai tracked oleh Git; mode filesystem sudah benar.
- Host port PostgreSQL 5432 masih dipakai container pengguna lain; `.env` lokal tetap menggunakan 55432 dan tidak diubah script.
- Session WAHA belum dibuat sesuai batasan Phase 0; tidak ada pairing atau pesan WhatsApp nyata.
- `shellcheck` tidak tersedia. Syntax Bash tetap tervalidasi dengan `bash -n`.
- Phase 0 tetap `IN_PROGRESS`; pertanyaan bisnis, CI, dan spike integrasi lainnya belum selesai.

**Next**
- Pulihkan/inisialisasi repository Git, lalu tambahkan perubahan melalui issue/branch/PR dan pastikan mode executable `run.sh` tercatat.
- Jalankan ShellCheck ketika tersedia dan lanjutkan exit criteria Phase 0 yang belum selesai.

### 1 September 2026 — Backend Folder and Docker Architecture Correction

**Goal**
- Memperbaiki nama folder Backend dan menjadikan Docker Compose tiga-service sebagai cara utama menjalankan stack tanpa membangun ulang source yang sudah benar.

**Changed**
- Memastikan target `pesenhub_be/` lama benar-benar kosong termasuk file tersembunyi, menghapusnya dengan `rmdir`, lalu memindahkan seluruh implementasi `BE/` menjadi `pesenhub_be/` menggunakan `mv` karena `.git/` bukan repository valid.
- Tidak mengubah atau menghapus `pesenhub_app/`.
- Menambah `pesenhub_be/Dockerfile` multi-stage dan `pesenhub_be/.dockerignore`.
- Memperbarui `pesenhub_be/docker-compose.yml`, `.env.example`, `Makefile`, `README.md`, dan `REQUIREMENTS.md` untuk stack `api`, `postgres`, dan `waha`.
- Memperbarui seluruh referensi struktur lama di root `PRD.md` dan `MEMORY.md` menjadi `pesenhub_be/` serta `pesenhub_app/`.

**Decisions**
- Builder dipatok ke `golang:1.26.0-alpine`, sesuai `go 1.26.0` pada `go.mod`; percobaan tag `golang:1.26.0-alpine3.24` gagal karena tag tersebut tidak tersedia.
- Runtime dipatok ke `alpine:3.24.1`, memasang hanya `ca-certificates` dan `tzdata`, serta berjalan sebagai `pesenhub` UID/GID 10001.
- Image runtime membawa binary statis `pesenhub-api`, binary migration `pesenhub-migrate`, SQL migration, dan asset web; tidak membawa Go toolchain atau source Go.
- PostgreSQL tetap `postgres:16-alpine`; WAHA tetap `devlikeapro/waha:latest-2026.8.1` dengan health endpoint `/api/server/status` yang tervalidasi HTTP 200.
- Stack utama berjalan melalui Docker Compose. Mode `go run ./cmd/api` tetap didokumentasikan untuk development host.

**Validation**
- `git status`: FAIL — `.git/` ada tetapi kosong dan bukan repository Git valid; `git mv` tidak tersedia.
- Audit `find pesenhub_be`: PASS — folder target lama kosong sebelum `rmdir`.
- `rmdir pesenhub_be` dan `mv BE pesenhub_be`: PASS.
- `go version`: PASS — `go1.26.0 linux/amd64` (hasil sesi tetap berlaku dan tidak ada instalasi/perubahan Go).
- `docker version`: PASS — Engine client/server `29.6.1` (hasil sesi tetap berlaku).
- `docker compose version`: PASS — `v5.2.0` (hasil sesi tetap berlaku).
- `go mod tidy` dengan cache default: FAIL — cache `/home/yoga/.cache/go-build` read-only di sandbox.
- `go mod tidy` dengan `GOCACHE=/tmp/pesenhub-go-cache`: PASS.
- `gofmt -w .`: PASS.
- `go vet ./...` dengan `GOCACHE=/tmp/pesenhub-go-cache`: PASS.
- `go test ./...` dalam sandbox: FAIL — `httptest` tidak diizinkan membuka listener localhost.
- `go test ./...` dengan izin localhost: PASS — seluruh package lulus.
- `docker compose config`: PASS.
- `docker compose build --no-cache api` dengan builder `golang:1.26.0-alpine3.24`: FAIL — tag image tidak ditemukan.
- `docker compose build --no-cache api` dengan builder `golang:1.26.0-alpine`: PASS.
- `docker compose up -d`: PASS.
- `docker compose up -d --build`: PASS — command utama tervalidasi.
- `docker compose ps`: PASS — `api`, `postgres`, dan `waha` berstatus `healthy`.
- `docker compose exec postgres pg_isready`: PASS — PostgreSQL menerima koneksi; command tanpa `-U` mencatat percobaan role `root` pada log, tetapi health service tetap valid.
- Migration container `down` lalu `up`: PASS.
- `curl /health/live`: PASS — HTTP 200, status `live`.
- `curl /health/ready`: PASS — HTTP 200, database `up`, WAHA `down`, status `degraded` karena session `default` sengaja tidak dibuat.
- `docker compose logs --no-color api|postgres|waha`: PASS — log diperiksa; tidak ditemukan credential aplikasi pada log API.
- `docker image inspect pesenhub-api:dev`: PASS — ukuran `10,329,314` byte (sekitar 9.85 MiB), user `pesenhub:pesenhub`, entrypoint `/app/pesenhub-api`.
- `docker history pesenhub-api:dev`: PASS — runtime berasal dari Alpine, binary/asset runtime saja; builder tidak masuk final layers.
- Pemeriksaan runtime dengan container sekali pakai: PASS — UID/GID 10001, `go-toolchain-absent`, `go-source-absent`.
- `docker compose stop -t 10 api` lalu start kembali: PASS — SIGTERM menghasilkan log `API stopped` sebelum container berhenti.
- Audit struktur dokumentasi: PASS — seluruh struktur aktif memakai `pesenhub_be/` dan `pesenhub_app/`; nama sumber lama hanya disebut pada catatan rename yang diwajibkan.

**Known Issues**
- Host port 5432 masih dipakai container pengguna `abel-postgres`. `.env` lokal yang diabaikan memakai `POSTGRES_HOST_PORT=55432`; API tetap mengakses `postgres:5432` di network Docker dan `.env.example` tetap mendokumentasikan default 5432.
- WAHA container sehat, tetapi belum ada session `default`; readiness API sengaja `degraded`. Tidak ada pairing atau pesan nyata.
- Root belum menjadi repository Git valid karena `.git/` kosong, sehingga rename tidak dapat direkam dengan `git mv` dan ignore belum dapat dibuktikan melalui `git status`.
- Phase 0 tetap `IN_PROGRESS`; pertanyaan bisnis, CI, serta spike Flutter, Hermes, Midtrans, dan webhook WAHA belum selesai.

**Next**
- Inisialisasi atau pulihkan metadata Git bila repository ini seharusnya versioned.
- Bebaskan port host 5432 atau sepakati override 55432 untuk development, lalu lanjutkan exit criteria Phase 0 yang masih terbuka.

### 1 September 2026 — Backend Phase 0 Foundation

**Goal**
- Menyiapkan fondasi Backend Golang, PostgreSQL, WAHA, migration, health check, dan Web Customer placeholder tanpa fitur order, Hermes, Midtrans, pairing, atau pengiriman WhatsApp.

**Changed**
- Membuat `pesenhub_be/.env.example`, `pesenhub_be/.gitignore`, `pesenhub_be/docker-compose.yml`, `pesenhub_be/go.mod`, `pesenhub_be/go.sum`, `pesenhub_be/Makefile`, `pesenhub_be/README.md`, dan `pesenhub_be/REQUIREMENTS.md`.
- Membuat bootstrap `pesenhub_be/cmd/api/main.go` dan runner migration `pesenhub_be/cmd/migrate/main.go`.
- Membuat package `pesenhub_be/internal/config`, `pesenhub_be/internal/database`, `pesenhub_be/internal/health`, `pesenhub_be/internal/httpserver`, dan `pesenhub_be/internal/waha`, termasuk unit test config, health, dan WAHA.
- Membuat migration reversible `pesenhub_be/migrations/000001_create_app_metadata.{up,down}.sql` dan placeholder `pesenhub_be/web/index.html`.
- Memperbarui `MEMORY.md`; tidak mengubah aplikasi Flutter yang sudah ada di `pesenhub_app/`.

**Decisions**
- Go yang benar-benar digunakan: `go1.26.0 linux/amd64`.
- PostgreSQL: `postgres:16-alpine`; default host port 5432 dan container port 5432.
- WAHA: `devlikeapro/waha:latest-2026.8.1`; host/container port 3000. Format tag terversi WAHA memakai prefix engine `latest-`.
- Pada sesi awal Golang divalidasi langsung di workspace; arsitektur terbaru menjalankan stack utama melalui Docker Compose dan tetap menyediakan mode lokal. `golang-migrate v4.19.1` dan `pgx v5.7.6` dipakai sebagai dependency utama.
- Database wajib `up` untuk readiness; WAHA tanpa session menghasilkan status `degraded` dengan HTTP 200. Pairing dan pengiriman pesan tidak dilakukan.

**Validation**
- `go version`: PASS — `go1.26.0 linux/amd64`.
- `docker version`: PASS — client/server dapat dipakai; CLI `29.6.1`.
- `docker compose version`: PASS — `v5.2.0`.
- `docker compose --env-file .env.example config`: PASS.
- `gofmt -w .`: PASS.
- `go mod tidy`: PASS setelah akses network dependency diizinkan.
- `go vet ./...`: PASS.
- `go test ./...`: PASS.
- `docker compose --env-file .env.example up -d postgres waha`: FAIL pada konfigurasi port default karena host port 5432 sudah dipakai container pengguna `abel-postgres`; WAHA tetap berhasil dijalankan.
- `DATABASE_PORT=55432 docker compose --env-file .env.example up -d postgres`: PASS sebagai validasi sementara tanpa mengubah default repository.
- `DATABASE_PORT=55432 docker compose --env-file .env.example ps`: PASS — PostgreSQL dan WAHA `healthy`.
- `go run ./cmd/migrate up` dengan `DATABASE_PORT=55432`: PASS.
- `go run ./cmd/migrate down` lalu `go run ./cmd/migrate up` dengan `DATABASE_PORT=55432`: PASS.
- `go run ./cmd/api` dengan `DATABASE_PORT=55432`: PASS — dijalankan langsung dari workspace.
- `curl http://localhost:8080/health/live`: PASS — HTTP 200, status `live`.
- `curl http://localhost:8080/health/ready`: PASS — HTTP 200, database `up`, WAHA `down`, status `degraded` karena tidak ada session yang dipasangkan.
- `curl http://localhost:8080/`: PASS — placeholder PesenHub tersaji.
- Penghentian API dengan SIGINT: PASS — log `API stopped` membuktikan graceful shutdown.

**Known Issues**
- Default port PostgreSQL 5432 sedang ditempati `abel-postgres`; service PesenHub tervalidasi pada override host port 55432. Container pengguna tidak dihentikan atau diubah.
- WAHA container sehat, tetapi readiness melaporkan WAHA `down` karena session `default` sengaja tidak dibuat/dipasangkan pada Phase 0.
- Repository root belum berupa Git repository, sehingga status perubahan Git dan efektivitas ignore belum dapat diverifikasi lewat `git status`.
- Exit criteria Phase 0 keseluruhan belum terpenuhi: pertanyaan bisnis, CI, spike Flutter, webhook WAHA/pesan dev, Hermes, dan Midtrans masih terbuka. Status tetap `IN_PROGRESS`.

**Next**
- Bebaskan port 5432 atau gunakan override development yang disepakati, lalu ulangi command Compose default.
- Kunci pertanyaan bisnis Phase 0 dan lanjutkan spike integrasi/CI yang belum dikerjakan tanpa memperluas ke implementasi fitur order.
