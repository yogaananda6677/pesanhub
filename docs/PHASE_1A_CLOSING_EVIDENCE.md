# Phase 1A Core Backend — Closing Evidence

Dokumen ini adalah bukti penutupan [Phase Issue #3](https://github.com/yogaananda6677/pesanhub/issues/3). Status `DONE` pada branch closing berlaku setelah Pull Request ini di-merge dan Issue #3 ditutup.

---

## 1. Scope yang Ditutup

Phase 1A menyediakan fondasi system of record untuk PesenHub di backend Golang dan PostgreSQL 16:
- REST API conventions, standard envelope, error codes, cursor pagination, dan idempotency middleware.
- Reversible database migrations (000001–000008).
- Customer profile, deduplikasi nomor HP Indonesia E.164, dan preference store.
- Katalog menu berstruktur kategori, menu item, modifier groups/options (min_select, max_select), versioning optimistik, dan kalkulasi harga backend.
- Order creation `CASHIER_MANUAL` dengan idempotency key, source tracking, dan transactional outbox.
- Order lifecycle state machine (`PENDING` -> `ACCEPTED` -> `PREPARING` -> `READY_FOR_PICKUP` -> `COMPLETED` / `CANCELLED` / `REJECTED`), validasi transisi legal, status history, dan outbox events.
- Unified order query, cursor-based pagination, filter multi-dimensi (source, status, date range), dan live queue snapshot.
- Native WebSocket real-time event streaming (`/ws/orders`) dengan RFC 6455 frame parsing, heartbeat ping/pong, role-aware broadcasting (PII redacted for KDS), dan outbox publishing.
- Customer Web ordering mobile-first (`/web`) tanpa akun dengan validasi nama/nomor HP, total preview backend, double-submit guard, dan tracking token opaque berawalan `trk_` (Invariant 11).
- Audit log append-only dan immutable untuk setiap mutasi order kritis dengan sanitasi PII (`MaskPhone`, token/secret redacted), transactional atomicity, dan query terotorisasi self-audited.

---

## 2. Child Issue Matrix

| Child Issue | Judul | PR | Status | Evidence |
|---|---|---|---|---|
| [#13](https://github.com/yogaananda6677/pesanhub/issues/13) | Tetapkan API convention, error response, pagination, dan versioning | [#81](https://github.com/yogaananda6677/pesanhub/pull/81) | CLOSED | `docs/API_CONVENTIONS.md`, `internal/httpapi/` |
| [#14](https://github.com/yogaananda6677/pesanhub/issues/14) | Desain domain model dan migration data inti | [#83](https://github.com/yogaananda6677/pesanhub/pull/83) | CLOSED | Migrations 000001 & 000002, `internal/domain/` |
| [#15](https://github.com/yogaananda6677/pesanhub/issues/15) | Implementasi identifikasi dan profil pelanggan | [#84](https://github.com/yogaananda6677/pesanhub/pull/84) | CLOSED | Migration 000003, `internal/customer/` |
| [#16](https://github.com/yogaananda6677/pesanhub/issues/16) | Implementasi menu, category, modifier, harga, dan availability | [#85](https://github.com/yogaananda6677/pesanhub/pull/85) | CLOSED | Migration 000004, `internal/catalog/` |
| [#17](https://github.com/yogaananda6677/pesanhub/issues/17) | Implementasi order creation CASHIER_MANUAL, source tracking, dan idempotency | [#86](https://github.com/yogaananda6677/pesanhub/pull/86) | CLOSED | Migration 000005, `internal/order/` |
| [#18](https://github.com/yogaananda6677/pesanhub/issues/18) | Implementasi lifecycle order, validasi transisi, dan audit status | [#87](https://github.com/yogaananda6677/pesanhub/pull/87) | CLOSED | Migration 000006, `internal/order/` |
| [#19](https://github.com/yogaananda6677/pesanhub/issues/19) | Implementasi unified order query dan filter antrean | [#88](https://github.com/yogaananda6677/pesanhub/pull/88) | CLOSED | Migration 000007, `internal/order/` |
| [#20](https://github.com/yogaananda6677/pesanhub/issues/20) | Implementasi WebSocket order event dan recovery | [#91](https://github.com/yogaananda6677/pesanhub/pull/91) | CLOSED | `internal/ws/`, `internal/order/publisher.go`, `docs/ORDER_EVENTS_WS.md` |
| [#21](https://github.com/yogaananda6677/pesanhub/issues/21) | Implementasi customer ordering web dan validasi identitas | [#92](https://github.com/yogaananda6677/pesanhub/pull/92) | CLOSED | Migration 000008, `web/`, `docs/CUSTOMER_WEB_ORDERING.md` |
| [#22](https://github.com/yogaananda6677/pesanhub/issues/22) | Implementasi audit log perubahan pesanan | [#93](https://github.com/yogaananda6677/pesanhub/pull/93) | CLOSED | `internal/order/audit.go`, `docs/ORDER_AUDIT_LOGS.md` |

---

## 3. Acceptance Criteria Verification for Phase Issue #3

| Kriteria #3 | Hasil | Evidence / Catatan |
|---|---|---|
| Migration dan domain inti tervalidasi | PASS | 8 migrasi up/down/up teruji via `./scripts/test-migrations.sh` tanpa drift |
| Order CASHIER_MANUAL dan CUSTOMER_WEB dapat dibuat tanpa duplikasi | PASS | Teruji pada `store_integration_test.go` dan `web_integration_test.go` dengan replay idempotency key |
| Lifecycle menolak transisi ilegal dan diaudit | PASS | Validasi state machine pada `service.go` dan integration test `audit_integration_test.go` |
| Unified query dan WebSocket menghasilkan event konsisten | PASS | Unified query pada PR #88 dan real-time dispatch teruji pada `ws_integration_test.go` |
| Seluruh child issue memiliki scope, dependency, test plan, dan Definition of Done | PASS | Child issues #13–#22 lengkap dan tervalidasi |
| Seluruh feature PR telah di-merge dan review conversation selesai | PASS | PR #81, #83, #84, #85, #86, #87, #88, #91, #92, #93 telah disquash-merge ke `main` |
| Backend CI, Mobile CI, serta integration test relevan lulus | PASS | Seluruh PR lulus 3 required checks CI; test script suite lulus lokal |
| Dokumentasi dan MEMORY diperbarui melalui Phase Closing PR | PASS ON MERGE | Dokumen evidence ini, PRD, dan MEMORY.md diselaraskan pada PR ini |

---

## 4. Validation Evidence

| Area | Command / Evidence | Hasil |
|---|---|---|
| Backend Format & Lints | `pesenhub_be/run.sh check` | PASS (0 warning, 0 error) |
| Backend Race Detection | `go test -race ./...` | PASS (0 race detected) |
| Reversible Migrations | `pesenhub_be/scripts/test-migrations.sh` | PASS (000001 s.d. 000008 siklus up/down/up bersih) |
| Order & Queue Integration | `pesenhub_be/scripts/test-orders.sh` | PASS (Order manual, query queue, WS event, Web order, Audit log lulus) |
| Web Accessibility & Responsiveness | `go test -v -run TestWebStaticAssetsAccessibilityAndResponsive ./internal/order/...` | PASS (Mobile viewport, semantic roles, aria-live) |
| OpenAPI 3.1.0 Contract | `python3 -c "import yaml; yaml.safe_load(open('docs/api/openapi.yaml'))"` | PASS (Valid YAML schema) |
| Flutter / Mobile Baseline | `flutter test` | PASS (Baseline mobile tetap hijau tanpa degradasi) |

---

## 5. Transisi ke Phase Berikutnya

Dengan selesainya Phase 1A:
- **Phase 1B — Cashier Mobile & Tablet (#4)** siap dimulai dengan child issues #23 s.d. #32 untuk implementasi UI POS/KDS di Flutter menggunakan kontrak REST dan WebSocket yang telah tersedia di Phase 1A.
