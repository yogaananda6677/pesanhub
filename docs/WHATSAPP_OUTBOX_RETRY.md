# WhatsApp Notification Outbox, Retry, and Failure Logging

Dokumentasi arsitektur penyimpanan pesan outbound WhatsApp (*durable outbox pattern*), siklus hidup retry dengan *exponential backoff*, kebijakan *dead-letter*, penanganan *crash recovery*, dan sanitasi error/PII pada Backend PesenHub (Issue #43, Phase 1C).

---

## 1. Latar Belakang & Prinsip Inti

1. **Decoupled Transport Invariant**: Kegagalan pengiriman WhatsApp ke gateway eksternal (WAHA) tidak boleh membatalkan (*rollback*) atau menggagalkan transaksi order yang sudah di-*commit* di backend.
2. **At-Most-Once Idempotency**: Setiap event notifikasi memiliki kunci idempoten unik (`order:<order_id>:type:<type>:v:<version>`). Pengiriman ulang atau event duplikat tidak akan menduplikasi pesan WhatsApp ke pelanggan.
3. **Zero AI Price Hallucination**: Konten notifikasi WhatsApp dihasilkan dari data snapshot transaksi yang sudah divalidasi backend, bukan teks bebas yang rawan halusinasi harga.
4. **Privacy & Log Redaction**: Nomor telepon pelanggan selalu dimasking (`MaskPhone`, format `+6281****7890`), dan tidak ada secret, token, atau raw payload yang disimpan di kolom error atau log.
5. **Durable & Crash-Resilient**: Seluruh antrean disimpan secara persisten di PostgreSQL table `order_notifications` dengan lock `FOR UPDATE SKIP LOCKED`.

---

## 2. Model Data & Migrasi `000015`

Migrasi `000015_create_waha_outbox_retry_logging.up.sql` memperluas tabel `order_notifications`:

```sql
ALTER TABLE order_notifications
    ADD COLUMN next_retry_at timestamptz,
    ADD COLUMN max_attempts integer NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
    ADD COLUMN error_category text CHECK (error_category IS NULL OR error_category IN (
        'TRANSIENT_TIMEOUT',
        'TRANSIENT_NETWORK',
        'TRANSIENT_PROVIDER',
        'SESSION_NOT_READY',
        'PERMANENT_VALIDATION',
        'PERMANENT_AUTH',
        'MAX_ATTEMPTS_EXCEEDED',
        'UNKNOWN'
    ));

ALTER TABLE order_notifications DROP CONSTRAINT IF EXISTS order_notifications_status_check;
ALTER TABLE order_notifications ADD CONSTRAINT order_notifications_status_check
    CHECK (status IN ('PENDING', 'PROCESSING', 'SENT', 'FAILED', 'SUPPRESSED', 'DEAD_LETTER'));

CREATE INDEX idx_order_notifications_outbox
    ON order_notifications (status, next_retry_at, created_at)
    WHERE status IN ('PENDING', 'PROCESSING', 'FAILED');
```

---

## 3. Status Lifecycle & State Machine

```
               +---------------------------------------+
               |  Event Trigger (Order Created/Status) |
               +---------------------------------------+
                                   |
                                   v
                             [ PENDING ]
                                   |
             +---------------------+---------------------+
             |                                           |
             v (Opt-Out / Conversation Paused)           v (Claimed for Delivery)
      [ SUPPRESSED ]                              [ PROCESSING ]
                                                         |
                 +-----------------------+---------------+-----------------------+
                 |                       |                                       |
                 v (200 OK)              v (Permanent Error / Max Attempts)      v (Transient Error)
             [ SENT ]             [ DEAD_LETTER ]                             [ FAILED ]
                                                                                 |
                                                                                 | (Backoff delay: next_retry_at)
                                                                                 v
                                                                           (Ready for next claim)
```

| Status | Deskripsi | Aksi Lanjutan |
| :--- | :--- | :--- |
| `PENDING` | Pesan baru masuk antrean outbox. | Diproses langsung atau diklaim worker. |
| `PROCESSING` | Sedang dikirim oleh worker. Dilindungi lock `SKIP LOCKED`. | Transisi ke `SENT`, `FAILED`, atau `DEAD_LETTER`. |
| `SENT` | Pesan berhasil terkirim dan diakui gateway WAHA (`provider_message_id` tersimpan). | **Terminal**. Panggilan berikutnya dengan kunci idempoten sama menjadi no-op. |
| `FAILED` | Mengalami kegagalan sementara (*transient*). Dijadwalkan ulang dengan `next_retry_at`. | Diklaim kembali oleh worker saat `now() >= next_retry_at`. |
| `SUPPRESSED` | Dibatalkan karena pelanggan opt-out (`STOP`) atau percakapan diambil alih staf (`HANDOFF` / `PAUSED`). | **Terminal**. Tidak dikirim ke WAHA. |
| `DEAD_LETTER` | Kegagalan permanen (validasi 400, auth 401/403) atau batas `max_attempts` tercapai. | **Terminal**. Membutuhkan penanganan manual / alert. |

---

## 4. Algoritma Exponential Backoff

Rumus penundaan retry:
$$\text{delay} = \text{baseDelay} \times 2^{\text{attempt} - 1}$$
Dibatasi oleh $\text{maxDelay}$ (default 60 detik) untuk mencegah delay tak hingga.

| Attempt | Delay (Base = 1s, Max = 60s) |
| :---: | :---: |
| 1 | 1 detik |
| 2 | 2 detik |
| 3 | 4 detik |
| 4 | 8 detik |
| 5 | 16 detik |
| 6 | 32 detik |
| 7+ | 60 detik (Capped) |

Jika `attempt >= max_attempts` (default 5), pesan otomatis dipindahkan ke status `DEAD_LETTER` dengan kategori `MAX_ATTEMPTS_EXCEEDED`.

---

## 5. Taksonomi Error & Klasifikasi Aman

Fungsi `ClassifyError(err)` memetakan error eksternal secara deterministik:

| Error Type | Category | Retryable? | Tindakan |
| :--- | :--- | :---: | :--- |
| `waha.ErrValidation` / 400 / 422 | `PERMANENT_VALIDATION` | Tidak | Langsung `DEAD_LETTER` |
| `waha.ErrAuthentication` / 401 / 403 | `PERMANENT_AUTH` | Tidak | Langsung `DEAD_LETTER` |
| `waha.ErrTimeout` / Deadline Exceeded | `TRANSIENT_TIMEOUT` | Ya | Jadwalkan ulang dengan backoff |
| `waha.ErrSessionNotReady` / 404 Absent | `SESSION_NOT_READY` | Ya | Jadwalkan ulang dengan backoff |
| `waha.ErrProvider` / 500 / 502 / 503 / 504 | `TRANSIENT_PROVIDER` | Ya | Jadwalkan ulang dengan backoff |
| Connection Refused / Network Glitch | `TRANSIENT_NETWORK` | Ya | Jadwalkan ulang dengan backoff |
| Other Unknown | `UNKNOWN` | Ya (hingga max attempt) | Jadwalkan ulang dengan backoff |

Fungsi `SanitizeError(err)` menghapus secret API key (`[REDACTED]`), memasking nomor telepon (`+6281****7890`), dan membatasi panjang teks maksimal 255 karakter sebelum disimpan di database.

---

## 6. Crash Recovery & Concurrency Safety

1. **Zero Row Lock Exhaustion**: Worker mengambil batch dengan kueri CTE pendek `FOR UPDATE SKIP LOCKED` dan segera mengubah status menjadi `PROCESSING`, melepaskan koneksi PostgreSQL sebelum melakukan panggilan HTTP ke WAHA.
2. **Multi-Worker Safety**: `FOR UPDATE SKIP LOCKED` memastikan beberapa replika worker tidak akan pernah memproses baris yang sama secara bersamaan.
3. **Startup Recovery**: Saat aplikasi dinyalakan ulang (*restart / crash*), `RecoverStaleProcessing(ctx, 0)` secara otomatis mereset seluruh baris berstatus `PROCESSING` kembali ke `FAILED` agar segera dijadwalkan ulang tanpa kehilangan job.
4. **Periodic Stale Sweep**: Worker secara berkala membersihkan baris `PROCESSING` yang menggantung lebih dari `staleThreshold` (default 2 menit).
