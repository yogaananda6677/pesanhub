# Phase 0 Product Decision Baseline

Dokumen ini adalah proposal keputusan untuk [Issue #75](https://github.com/yogaananda6677/pesanhub/issues/75). Status seluruh keputusan adalah `EFFECTIVE_ON_MERGE`: keputusan belum berlaku ketika hanya berada pada branch/PR, dan menjadi baseline setelah Pull Request direview serta di-merge oleh Owner.

## Ringkasan Keputusan

| ID | Keputusan | Baseline MVP | Owner | Status |
| --- | --- | --- | --- | --- |
| PD-001 | Scope outlet | Satu outlet | Product Owner | EFFECTIVE_ON_MERGE |
| PD-002 | Perangkat operasional | Satu perangkat kasir dan satu perangkat KDS; maksimum tiga perangkat staf aktif sebagai target uji MVP | Product Owner | EFFECTIVE_ON_MERGE |
| PD-003 | Fulfillment | Pickup di outlet saja | Product Owner | EFFECTIVE_ON_MERGE |
| PD-004 | Order dianggap sah | Setelah submit/konfirmasi eksplisit, validasi Backend, dan transaksi persistence berhasil | Product Owner + Lead Engineer | EFFECTIVE_ON_MERGE |
| PD-005 | Pembayaran MVP | Tunai dan Midtrans QRIS | Product Owner | EFFECTIVE_ON_MERGE |
| PD-006 | Local database Flutter | SQLite; package dipilih pada #32 | Lead Engineer | EFFECTIVE_ON_MERGE |
| PD-007 | Risiko WAHA | Diterima terbatas untuk development/pilot dengan nomor khusus dan exit trigger | Product Owner | EFFECTIVE_ON_MERGE |
| PD-008 | Status canonical | Menggunakan vocabulary ringkas pada bagian Status | Product Owner + Lead Engineer | EFFECTIVE_ON_MERGE |

## Traceability dan Masa Berlaku

| Open question | Decision | Owner | Review/expiry |
| --- | --- | --- | --- |
| Q-001 | PD-001 — satu outlet | Product Owner | Tinjau ulang ketika outlet kedua dijadwalkan atau sebelum perencanaan pasca-MVP |
| Q-002 | PD-002 — satu kasir + satu KDS; target uji maksimum tiga perangkat staf | Product Owner | Tinjau ulang ketika kebutuhan perangkat keempat terverifikasi atau sebelum perencanaan pasca-MVP |
| Q-003 | PD-003 — pickup-only | Product Owner | Tinjau ulang ketika delivery masuk roadmap atau sebelum perencanaan pasca-MVP |
| Q-004 | PD-004 — order sah setelah konfirmasi, validasi, dan commit atomik | Product Owner | Berlaku sepanjang MVP; perubahan memerlukan decision record baru sebelum contract/schema diubah |
| Q-005 | PD-005 — Midtrans QRIS | Product Owner | Tinjau ulang sebelum kanal Midtrans lain diaktifkan atau sebelum perencanaan pasca-MVP |
| Q-006 | PD-006 — SQLite | Lead Engineer | Validasi package pada #32; keputusan engine kedaluwarsa bila spike gagal memenuhi kriteria wajib |
| Q-008 | PD-007 — WAHA terbatas untuk development/pilot | Product Owner | Kedaluwarsa segera saat salah satu exit trigger tercapai; wajib ditinjau sebelum data production dipakai |
| Q-009 | PD-005 — customer web menawarkan cash-at-pickup dan QRIS saat integrasi siap | Product Owner | Tinjau ulang sebelum metode lain ditambahkan atau sebelum perencanaan pasca-MVP |

Tidak ada keputusan yang ditunda tanpa batas waktu. Review/expiry di atas adalah batas berbasis kejadian karena tanggal delivery MVP belum dikunci menjadi tanggal kalender. Sampai PR ini di-merge, baris terkait di `MEMORY.md` tetap berstatus `PROPOSED`.

## PD-001 — Satu Outlet

MVP hanya melayani satu outlet. Model dan API tidak perlu membawa tenant switching atau konsolidasi multi-outlet pada setiap alur. Primary key tetap tidak bergantung pada nama outlet agar migrasi masa depan memungkinkan.

Tidak termasuk:

- Dashboard lintas outlet.
- Transfer order/stok antar-outlet.
- Role dan konfigurasi tenant kompleks.

Trigger evaluasi ulang: outlet kedua benar-benar dijadwalkan atau kebutuhan isolasi tenant menjadi requirement terverifikasi.

## PD-002 — Perangkat Operasional

Baseline operasional adalah satu perangkat kasir dan satu perangkat KDS. Sistem harus diuji dengan maksimum tiga perangkat staf aktif bersamaan agar WebSocket, optimistic concurrency, dan duplicate prevention tidak hanya benar pada single-device scenario.

Perangkat dapat berupa ponsel atau tablet. Role/permission ditentukan oleh akun staf, bukan jenis perangkat. Tidak ada device management/MDM pada MVP.

## PD-003 — Pickup Only

MVP hanya mendukung `PICKUP`. Pelanggan memesan melalui customer web, WhatsApp, atau kasir dan mengambil pesanan di outlet.

Delivery tidak diaktifkan karena memerlukan alamat tervalidasi, wilayah layanan, ongkir, kurir, SLA, proof of delivery, serta penanganan kegagalan yang belum disepakati. Field fulfillment tetap dirancang eksplisit sehingga enum baru dapat ditambahkan melalui migration/versioned contract pada phase berikutnya.

## PD-004 — Kapan Order Dianggap Sah

Order sah ketika seluruh kondisi berikut terpenuhi:

1. Pengguna/channel melakukan submit atau konfirmasi eksplisit.
2. Backend memvalidasi source, item, availability, modifier, jumlah, fulfillment, dan input wajib.
3. Backend menghitung total final.
4. Header, item snapshot, audit awal, dan outbox event berhasil disimpan atomik.
5. Backend mengembalikan `order_id`, version, dan status awal `PENDING`.

Aturan per sumber:

- `CASHIER_MANUAL`: sah setelah kasir menekan submit dan Backend commit.
- `CUSTOMER_WEB`: sah setelah pelanggan menyetujui review, submit idempotent, dan Backend commit.
- `WHATSAPP`: percakapan/extraction tetap draft; sah hanya setelah pelanggan mengonfirmasi ringkasan lengkap dan Backend commit.

Pembayaran bukan syarat universal agar order tercatat. Payment status dipisahkan dan policy penerimaan/produksi berdasarkan pembayaran dapat dikonfigurasi kemudian tanpa menggabungkan kedua state machine.

## PD-005 — Tunai dan Midtrans QRIS

Metode pembayaran MVP:

- `CASH`: dicatat staf berwenang; status awal `UNPAID`, menjadi `PAID` setelah penerimaan tunai dikonfirmasi.
- `MIDTRANS_QRIS`: dibuat Backend memakai nominal server-side; status hanya berubah berdasarkan webhook Midtrans yang tervalidasi dan idempotent.

Keduanya tersedia untuk `CASHIER_MANUAL`. Customer web dan WhatsApp boleh menawarkan tunai saat pickup serta QRIS setelah integrasi terkait siap. Kanal Midtrans selain QRIS, split payment, partial refund, dan refund otomatis tidak termasuk MVP.

## PD-006 — SQLite untuk Local Store

SQLite dipilih sebagai baseline karena kebutuhan lokal bersifat relational dan transactional: menu/category/modifier, queue snapshot, order/item, outbox berurutan, version, dan migration. SQLite juga mendukung constraint, index, transaction, serta inspeksi data test yang matang.

Engine SQLite tersedia pada platform target Android/iOS melalui adapter Flutter, tetapi dukungan platform akhir tetap bergantung pada package yang dipilih. Karena itu evidence package-specific—termasuk background isolate dan migration lintas versi—menjadi exit gate #32, bukan asumsi pada keputusan ini.

Issue #32 tetap wajib melakukan spike package Flutter dan memilih library berdasarkan:

- Dukungan Android/iOS dan versi Flutter terkunci.
- Migration schema dan transaction API.
- Query/filter antrean dan relasi order-item.
- Isolate/background synchronization.
- Testability dan maintenance package.

Isar tidak dipilih untuk MVP. Perubahan engine membutuhkan ADR baru dan migration plan; tidak boleh diganti hanya karena preferensi implementasi.

## PD-007 — Batas Risiko WAHA

WAHA diterima untuk development dan pilot MVP dengan batasan:

- Gunakan nomor khusus yang bukan nomor personal/utama outlet sampai pilot disetujui.
- Jangan pairing otomatis atau menyimpan QR/session pada repository, log, Issue, atau artifact.
- Terapkan webhook authentication bila versi mendukung, deduplication, rate limit, audit redacted, bounded retry, pause automation, dan human handoff.
- Sediakan cara menghentikan automation tanpa menghentikan pencatatan order manual/customer web.
- Informasikan kepada Owner bahwa gateway tidak resmi dapat mengalami disconnect, perubahan kompatibilitas, atau pembatasan akun.

Exit trigger menuju WhatsApp Business Platform resmi:

- Akun diblokir/dibatasi atau reliability pilot tidak memenuhi target.
- Provider tidak dapat memenuhi authentication, privacy, retention, atau audit requirement.
- Volume/operasi outlet memerlukan dukungan dan SLA resmi.
- Kebijakan Meta/provider berubah sehingga penggunaan WAHA tidak dapat diterima.

Penerimaan ini bukan izin menggunakan data pelanggan production sebelum privacy/security review #58 selesai.

## PD-008 — Status Canonical

### Order Status

```text
PENDING
ACCEPTED
PREPARING
READY_FOR_PICKUP
COMPLETED
REJECTED
CANCELLED
```

State machine minimum:

```text
PENDING → ACCEPTED → PREPARING → READY_FOR_PICKUP → COMPLETED
PENDING → REJECTED
PENDING | ACCEPTED → CANCELLED
```

Cancellation setelah `PREPARING` memerlukan policy/authorization eksplisit dan tidak menjadi transition default.

`DRAFT` dan `PENDING_CONFIRMATION` adalah state percakapan/order draft sebelum entitas order sah, bukan status pada order final. Istilah lama dipetakan sebagai berikut:

- `IN_PREPARATION` → `PREPARING`
- `READY` → `READY_FOR_PICKUP`

### Payment Status

```text
UNPAID
PENDING_PAYMENT
PAID
FAILED
EXPIRED
REFUNDED
```

Istilah lama `PENDING` pada payment dipetakan ke `PENDING_PAYMENT`. `PARTIALLY_REFUNDED` ditunda di luar MVP. Order status tidak berubah otomatis hanya karena payment menjadi `PAID`.

### Order Source

```text
WHATSAPP
CASHIER_MANUAL
CUSTOMER_WEB
```

`GOFOOD`, `GRABFOOD`, dan `SHOPEEFOOD` tetap reserved roadmap dan belum diterima endpoint MVP sebelum kontrak resmi diverifikasi.

## Dampak terhadap Issue Berikutnya

| Issue | Dampak setelah baseline efektif |
| --- | --- |
| #13 | Kontrak API memakai fulfillment/status/source canonical di atas |
| #14 | Migration membatasi MVP satu outlet dan memakai status canonical |
| #17 | Manual order sah setelah Backend commit; cash/QRIS tetap state terpisah |
| #18 | State machine dan optimistic version mengikuti PD-008 |
| #21 | Customer web pickup-only dengan cash-at-pickup/QRIS saat integrasi siap |
| #23/#30 | UI mobile/tablet memprioritaskan satu kasir dan satu KDS |
| #32 | Memilih package SQLite dan membuktikan migration/transaction/background support |
| #36–#43 | WAHA mengikuti batas pilot, pause/handoff, deduplication, dan exit trigger |
| #44–#47 | Payment hanya cash dan Midtrans QRIS pada MVP |
| #58 | Security/privacy review menjadi gate sebelum data production digunakan |

## Definition of Done Keputusan

- [ ] Owner mereview seluruh PD-001–PD-008.
- [ ] Owner meminta perubahan jika baseline operasional tidak sesuai kondisi outlet.
- [ ] Pull Request mendapat approval formal dan di-merge.
- [ ] Issue #76 menyelaraskan PRD dan MEMORY setelah keputusan efektif.
- [ ] Dependency issue tidak dimulai memakai asumsi yang bertentangan.
