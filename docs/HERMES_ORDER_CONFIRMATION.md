# Hermes WhatsApp Order Confirmation & Finalization Architecture

Dokumen ini mendokumentasikan implementasi dan aturan bisnis untuk konfirmasi pesanan pelanggan WhatsApp serta pembuatan order final ber-source `WHATSAPP` pada PesenHub.

---

## 1. Prinsip Utama dan Invariants

1. **Backend Golang adalah System of Record**:
   Hermes dan LLM tidak memiliki akses langsung ke database atau wewenang menetapkan harga.
2. **Zero Price Hallucination**:
   Harga unit, delta modifier, subtotal, dan total amount selalu dihitung secara deterministik oleh backend melalui tabel `menus` dan `modifier_options` (`FOR SHARE`).
3. **No Explicit Confirmation, No Final Order**:
   Tanpa persetujuan eksplisit dari pelanggan (seperti "Ya", "Iya", "Oke", "Setuju", "Benar"), tidak boleh ada order final yang dibuat di database.
4. **Stale Draft & Catalog Revalidation**:
   Sebelum draft dikonversi menjadi order final, status stok dan harga item/modifier divalidasi ulang ke katalog aktif. Jika terjadi perubahan harga atau menu habis, konversi dibatalkan, draft diperbarui dengan total baru, dan pelanggan diminta mengonfirmasi ulang.
5. **Idempotent Order Conversion**:
   Setiap order WhatsApp memiliki idempotency key terikat percakapan (`wa-conf-{conv_id}-{draft_version}`). Replay atau duplikasi webhook WAHA tidak akan membuat order ganda (`orders.source = 'WHATSAPP'`, `UNIQUE (source, idempotency_key)`).

---

## 2. State Machine Konfirmasi

```
[COLLECTING]
      │
      ├─(Ada ambiguitas)──► [AWAITING_CLARIFICATION]
      │                              │
      │                     (Semua terjawab)
      ▼                              ▼
 [READY_FOR_CONFIRMATION] ◄──────────┘
      │
      ├─► [IntentConfirm]
      │        │
      │        ├─► (Draft Stale / Harga Berubah) ─► Update draft & versi,
      │        │                                    minta review total baru
      │        │                                    (tetap di READY_FOR_CONFIRMATION)
      │        │
      │        └─► (Draft Fresh) ─────────────────► Buat Order WHATSAPP (idempotent),
      │                                             Kirim nomor order & tracking URL,
      │                                             Status: [COMPLETED]
      │
      ├─► [IntentCancel] ─────────────────────────► Draft dibatalkan,
      │                                             Status: [COLLECTING]
      │
      ├─► [IntentModify] ─────────────────────────► Merge/ekstraksi perubahan,
      │                                             Tampilkan summary baru
      │
      └─► [IntentUnknown] ────────────────────────► Kirim prompt penegasan,
                                                    TIDAK membuat order
```

---

## 3. Klasifikasi Intent Pelanggan (`DetectConfirmationIntent`)

Sistem mengklasifikasikan pesan masuk saat berada pada state `READY_FOR_CONFIRMATION`:
- **`IntentConfirm`**: Kata persetujuan bahasa Indonesia, e.g. `ya`, `iya`, `oke`, `ok`, `setuju`, `benar`, `betul`, `siap`, `lanjut`, `gas`, `bungkus`, `sudah benar`, `sesuai`, `ya kak`, `oke min`, `proses`.
- **`IntentCancel`**: Kata pembatalan, e.g. `batal`, `batalkan`, `gak jadi`, `ga jadi`, `cancel`, `batalin`, `tidak jadi`.
- **`IntentModify`**: Kata modifikasi pesanan, e.g. `ganti`, `ubah`, `tambah`, `kurang`, `tukar`, `revisi`.
- **`IntentUnknown`**: Kalimat pertanyaan di luar konfirmasi, e.g. "berapa lama ya?", "lokasinya di mana?", "halo".

---

## 4. Atribut Order `WHATSAPP`

Ketika order dibuat melalui `order.Service.CreateWhatsApp`:
- `source`: `'WHATSAPP'`
- `fulfillment`: `'PICKUP'` (sesuai check constraint database)
- `status`: `'PENDING'` (menunggu konfirmasi staf/kasir outlet)
- `version`: `1`
- `customer_name_snapshot`: Nama pelanggan atau default `'Pelanggan WhatsApp'`
- `customer_phone_snapshot`: Nomor HP terformat E.164 (`+628...`)
- `subtotal_amount` & `total_amount`: Total harga pasti hasil kalkulasi backend
- `public_tracking_token`: Token acak unik `trk_...` untuk memantau status pesanan tanpa login
- `order_status_history`: Tercatat entri awal dengan `actor_type = 'AGENT'`, `to_status = 'PENDING'`, `order_version = 1`
- `audit_logs`: Tercatat audit `ORDER_CREATED` dengan `actor_type = 'AGENT'`
- `outbox_events`: Menerbitkan event `ORDER_CREATED` untuk broadcast real-time WebSocket kasir dan tablet KDS
