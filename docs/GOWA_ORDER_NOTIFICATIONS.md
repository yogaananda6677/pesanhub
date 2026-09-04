# GOWA Order Confirmation & Completion Notifications

Dokumentasi arsitektur dan operasional pengiriman notifikasi WhatsApp pelanggan untuk memenuhi **Issue #42** (bagian dari Parent Epic: #1, Parent Phase: #5).

---

## 1. Prinsip dan Invarian Utama

1. **Backend Golang System of Record**:
   - Seluruh mutasi status order dan kalkulasi harga berasal dari Backend Golang.
   - Kegagalan transport GOWA (timeout, error 500/503, session terputus) **TIDAK BOLEH** menggagalkan atau me-rollback transaksi domain pesanan yang sudah di-commit.
2. **At-Most-Once Delivery per Template Version**:
   - Setiap notifikasi memiliki kunci idempoten unik format `order:<order_id>:type:<type>:v:<version>` dengan constraint unik di PostgreSQL (`order_notifications.idempotency_key`).
   - Replay event atau pemanggilan berulang tidak akan memicu pengiriman pesan kedua ke GOWA.
3. **Zero AI Price Hallucination**:
   - Seluruh pesan notifikasi dibuat menggunakan template deterministik backend.
   - Angka nominal, rincian modifier, dan total tagihan diambil langsung dari snapshot pesanan database terverifikasi.
4. **Proteksi Privasi & Redaksi PII**:
   - Nomor telepon pelanggan selalu disamarkan dalam log (`MaskPhone`: `+62812****7890`).
   - Tidak ada token, secret, atau raw payload kredensial yang dicatat pada log aplikasi.
5. **Guard Opt-Out**:
   - Pelanggan yang terdaftar di tabel `customer_opt_outs` tidak menerima pesan otomatis (`status = 'SUPPRESSED'`, `reason = 'CUSTOMER_OPTED_OUT'`).
6. **Guard Percakapan Dijeda / Handoff Staf**:
   - Jika percakapan pelanggan berstatus `is_paused = true`, `status IN ('PAUSED', 'HANDOFF')`, atau `handoff_status IN ('PENDING', 'ASSIGNED')`, notifikasi otomatis ditekan (`status = 'SUPPRESSED'`, `reason = 'CONVERSATION_PAUSED'` atau `'HANDOFF_ACTIVE'`) agar tidak mengganggu interaksi staf manusia.

---

## 2. Alur Sistem (System Flow)

```
Order Domain Event (Committed Transaction)
        │
        ├─► 1. Post-Commit Hook: StatusTransition ("COMPLETED" / "ACCEPTED")
        │
        ├─► 2. Idempotency Check (order_notifications table)
        │      └─ Jika duplicate: berhenti (IsDuplicate = true, status existing)
        │
        ├─► 3. Opt-Out Check (customer_opt_outs table)
        │      └─ Jika opted-out: Simpan record status = SUPPRESSED (CUSTOMER_OPTED_OUT)
        │
        ├─► 4. Conversation State Check (agent_conversations table)
        │      └─ Jika paused/handoff: Simpan record status = SUPPRESSED (CONVERSATION_PAUSED / HANDOFF_ACTIVE)
        │
        ├─► 5. Render Approved Template (v1)
        │
        └─► 6. Send via GOWA Client (POST /send/message)
               ├─ Success: Simpan status = SENT (provider_message_id)
               └─ Failure (Timeout / 5xx): Simpan status = FAILED (last_error)
                  └─ Domain order tetap sukses (HTTP 200) tanpa rollback!
```

---

## 3. Template Pesan yang Disetujui (Approved Templates v1)

### 3.1. CONFIRMATION (Pesanan Dibuat)
```
🔔 *Konfirmasi Pesanan PesenHub*

Halo *{{CustomerName}}*, pesanan Anda telah berhasil dibuat!

*No. Pesanan:* {{OrderNumber}}
*Metode:* Ambil di Outlet (PICKUP)

*Rincian Pesanan:*
• {{Quantity}}x {{ItemName}} ({{Modifiers}}) — {{LineTotalFormatted}}
  Catatan: {{Notes}}

*Total Pembayaran:* {{TotalAmountFormatted}}

Pantau status pesanan Anda melalui tautan berikut:
{{TrackingURL}}

Terima kasih telah memesan di PesenHub! 🙏
```

### 3.2. ACCEPTED (Pesanan Diterima & Dimasak)
```
🍳 *Pesanan Diterima — PesenHub*

Halo *{{CustomerName}}*, pesanan Anda *{{OrderNumber}}* telah diterima oleh outlet dan sedang dipersiapkan di dapur.

Pantau status pesanan:
{{TrackingURL}}

Mohon ditunggu, kami akan memberi tahu jika pesanan sudah siap diambil.
```

### 3.3. COMPLETED (Pesanan Siap Diambil)
```
✅ *Pesanan Siap Diambil — PesenHub*

Halo *{{CustomerName}}*, pesanan Anda *{{OrderNumber}}* telah SELESAI dan siap diambil di outlet!
Silakan tunjukkan nomor pesanan ini ke kasir saat pengambilan.

Terima kasih telah memesan di PesenHub! 🙏
```

---

## 4. Skema Database (Migration 000014)

### `customer_opt_outs`
| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | uuid PRIMARY KEY | ID unik opt-out |
| `phone_e164` | text NOT NULL UNIQUE | Nomor E.164 (`+628...`) |
| `reason` | text | Alasan opt-out |
| `created_at` | timestamptz | Timestamp UTC |

### `order_notifications`
| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | uuid PRIMARY KEY | ID record notifikasi |
| `order_id` | uuid REFERENCES orders(id) | Relasi ke order domain |
| `customer_phone` | text NOT NULL | Nomor telepon penerima |
| `notification_type` | text NOT NULL | `'CONFIRMATION'`, `'ACCEPTED'`, `'COMPLETED'` |
| `template_version` | text NOT NULL DEFAULT 'v1' | Versi template |
| `idempotency_key` | text NOT NULL UNIQUE | `order:<id>:type:<type>:v:<ver>` |
| `message_text` | text NOT NULL | Teks pesan final yang dirender |
| `status` | text NOT NULL DEFAULT 'PENDING' | `'PENDING'`, `'SENT'`, `'FAILED'`, `'SUPPRESSED'` |
| `suppress_reason` | text | `'CUSTOMER_OPTED_OUT'`, `'CONVERSATION_PAUSED'`, `'HANDOFF_ACTIVE'` |
| `provider_message_id` | text | ID pesan dari provider GOWA |
| `attempts` | integer DEFAULT 0 | Jumlah percobaan pengiriman |
| `last_error` | text | Kategori/pesan error tersanitasi |
| `sent_at` | timestamptz | Waktu pesan berhasil dikirim |
| `created_at` | timestamptz | Timestamp pembuatan |
| `updated_at` | timestamptz | Timestamp pembaruan |

---

## 5. Taksonomi Error & Pemisahan Kegagalan

| Skenario | Kode Status | Status Notifikasi | Dampak ke Status Order |
|---|---|---|---|
| GOWA 200/201 OK | HTTP 200 | `SENT` | Committed `COMPLETED` |
| GOWA 500/502/503 | HTTP 200 | `FAILED` (logged) | Committed `COMPLETED` (No rollback) |
| GOWA Timeout | HTTP 200 | `FAILED` (logged) | Committed `COMPLETED` (No rollback) |
| Customer Opted-Out | HTTP 200 | `SUPPRESSED` | Committed `COMPLETED` (No message sent) |
| Conversation Paused / Handoff | HTTP 200 | `SUPPRESSED` | Committed `COMPLETED` (No message sent) |
| Invalid Phone Format | HTTP 200 | `FAILED` | Committed `COMPLETED` (No message sent) |
| Duplicate Event Replay | HTTP 200 | `SENT` / `SUPPRESSED` (dedup) | Idempotent ACK (No duplicate send) |
