# Agent Project Memory

## PesenHub — Outlet Order Management System

Dokumen ini adalah memori kerja proyek untuk manusia dan coding agent. Baca dokumen ini bersama `PRD.md` sebelum merencanakan atau mengubah kode. Perbarui setelah setiap sesi kerja yang menghasilkan perubahan material.

> Jangan menandai pekerjaan sebagai selesai hanya karena kode sudah ditulis. Status `DONE` hanya boleh digunakan setelah acceptance criteria dan validasi phase lulus.

## 1. Project Snapshot

| Field | Current value |
| --- | --- |
| Product | PesenHub |
| Current phase | Phase 1A — Core Backend |
| Current status | IN_PROGRESS |
| MVP target | 30 hari sejak kickoff |
| Last updated | 3 September 2026 |
| Updated by | Issue #13 API conventions |

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
| [1A — #3](https://github.com/yogaananda6677/pesanhub/issues/3) | Core Backend | IN_PROGRESS | 2026-09-03 | — | Issue #13 API conventions |
| [1B — #4](https://github.com/yogaananda6677/pesanhub/issues/4) | Cashier Mobile & Tablet | NOT_STARTED | — | — | Menunggu kontrak 1A |
| [1C — #5](https://github.com/yogaananda6677/pesanhub/issues/5) | WhatsApp, Agent & Payment | NOT_STARTED | — | — | Menunggu domain 1A |
| [1D — #6](https://github.com/yogaananda6677/pesanhub/issues/6) | MVP Integration & Release | NOT_STARTED | — | — | Menunggu 1A–1C |
| [2 — #7](https://github.com/yogaananda6677/pesanhub/issues/7) | Food Aggregator Integration | NOT_STARTED | — | — | Menunggu MVP stabil dan kontrak resmi |
| [3 — #8](https://github.com/yogaananda6677/pesanhub/issues/8) | Production Hardening | NOT_STARTED | — | — | Menunggu hasil pilot dan target kapasitas |

Status yang diperbolehkan: `NOT_STARTED`, `IN_PROGRESS`, `BLOCKED`, `DONE`.

## Current GitHub Work

- Epic Issue: [#1](https://github.com/yogaananda6677/pesanhub/issues/1)
- Phase Issue: [#3 — Phase 1A Core Backend](https://github.com/yogaananda6677/pesanhub/issues/3)
- Child Issues: #13–#22
- Phase Roadmap: [#2](https://github.com/yogaananda6677/pesanhub/issues/2), [#3](https://github.com/yogaananda6677/pesanhub/issues/3), [#4](https://github.com/yogaananda6677/pesanhub/issues/4), [#5](https://github.com/yogaananda6677/pesanhub/issues/5), [#6](https://github.com/yogaananda6677/pesanhub/issues/6), [#7](https://github.com/yogaananda6677/pesanhub/issues/7), [#8](https://github.com/yogaananda6677/pesanhub/issues/8)
- Current Issue: [#13 — API convention, error response, pagination, dan versioning](https://github.com/yogaananda6677/pesanhub/issues/13)
- Current Branch: `feat/13-api-conventions`
- Pull Request: `NOT_CREATED`
- Merged Pull Requests: [#77](https://github.com/yogaananda6677/pesanhub/pull/77), [#78](https://github.com/yogaananda6677/pesanhub/pull/78), [#79](https://github.com/yogaananda6677/pesanhub/pull/79), [#80](https://github.com/yogaananda6677/pesanhub/pull/80), [#81](https://github.com/yogaananda6677/pesanhub/pull/81)
- Status: `IN_PROGRESS`
- Exit Criteria: lihat acceptance criteria #13; Phase 1A tetap terbuka sampai seluruh child issue dan Phase Closing PR #3 selesai
- Validation: serializer/error mapping, pagination, request ID, panic contract, Backend check/race/vet, dan OpenAPI parse lulus lokal
- Blocker: tidak ada untuk #13
- Next Issue: #14 setelah #13 direview dan di-merge

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
- Buka PR #13; setelah merge lanjut #14 untuk domain model dan migration inti.

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
