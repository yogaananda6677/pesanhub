# Conflict Handling & Duplicate Prevention Architecture

## 1. Overview
In a multi-device POS and KDS system with offline operation and unpredictable network connectivity, data conflicts and duplicate events are expected scenarios. This document formalizes the conflict classification matrix, deduplication strategies, server-wins invariants, and audit logging rules implemented in PesenHub Flutter application to satisfy **Issue #34**.

---

## 2. Invariants & Rules

1. **Server-Wins Invariant for Payment & Terminal States**:
   - Backend Golang is the single source of truth for financial transactions and final order states.
   - If the server indicates an order is `PAID`, local offline state (even if `UNPAID`) cannot revert it.
   - If the server indicates an order is in a terminal state (`COMPLETED`, `CANCELLED`, `REJECTED`), local mutations cannot reopen or alter the order lifecycle.
   - Strategy: **`SERVER_WINS`** (Forced reload, discarding invalid local lifecycle transitions).

2. **Classification Matrix**:
   | Conflict Category | Condition | Safety | Resolution Strategy | UI Experience |
   |---|---|---|---|---|
   | **Final State Overwrite** | Server is `COMPLETED`, `CANCELLED`, or `REJECTED` while client attempted a transition | Unsafe | `SERVER_WINS` / `FORCE_RELOAD` | Warning banner: "Pesanan sudah selesai/dibatalkan di server. Memuat versi terbaru..." |
   | **Payment Reversion** | Server is `PAID` while client attempted status change on `UNPAID` | Unsafe | `SERVER_WINS` / `FORCE_RELOAD` | Warning banner: "Pembayaran telah dikonfirmasi di server. Memuat versi terbaru..." |
   | **Version Drift** | Server version is ahead ($V_{\text{server}} > V_{\text{local}}$) and lifecycle state has progressed | Unsafe | `SERVER_WINS` / `FORCE_RELOAD` | Alert banner: "Pesanan telah diperbarui oleh perangkat lain. Memuat data terbaru..." |
   | **Safe Editable Field** | Order status is identical, but non-lifecycle fields differ (e.g. `takeawayNotes` edited concurrently) | Safe | `USER_CHOICE` (`clientWins`, `serverWins`, `merge`) | Interactive Modal: side-by-side field comparison with 3 choices |

3. **Deduplication Invariants**:
   - **Event Deduplication**: Every event has a unique event ID or composite key `(order_id, version, status)`. Processed events are cached in an LRU memory buffer. Duplicate events are silently acknowledged without triggering re-render cascades or audio alerts.
   - **Timeline Deduplication**: Status timeline events with duplicate status transitions or identical timestamps are filtered to preserve a clean, monotonic progression (`ACCEPTED` -> `PREPARING` -> `READY_FOR_PICKUP` -> `COMPLETED`).
   - **Queue Card Deduplication**: `QueueController` maintains a map keyed by `order.id`. Incoming events with version $V_{\text{event}} \le V_{\text{existing}}$ with identical status are dropped.

4. **Sanitized Conflict Audit Logging (Invariant 11)**:
   - All conflict resolutions are recorded locally in SQLite table `conflict_logs`.
   - Customer phone numbers are strictly masked (`0812****7890`).
   - Authentication tokens, secret keys, or private customer data are never stored in log payloads.

