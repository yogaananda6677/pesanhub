# GOWA Inbound Messages, Number Normalization, and Deduplication

Dokumentasi arsitektur penyerapan pesan masuk GOWA (WhatsApp) pada backend PesenHub untuk memenuhi Issue #37.

## Arsitektur Alur Pesan Masuk

```
GOWA Webhook Event (POST /webhooks/gowa)
   │
   ├─► 1. Verifikasi `X-Hub-Signature-256` (HMAC-SHA256 atas raw body)
   │
   ├─► 2. Lapis 1 Deduplikasi: In-Memory Replay Guard (hash raw body, TTL 10m)
   │      └─ Jika duplikat: HTTP 204 (X-PesenHub-Deduplicated: true)
   │
   ├─► 3. Payload Parsing & is_from_me Check
   │      └─ Jika is_from_me == true (pesan bot sendiri): diabaikan, HTTP 204
   │
   ├─► 4. Normalisasi Nomor & Kebijakan Karantina
   │      ├─ Format WhatsApp JID diurai (strip `@c.us`, `@s.whatsapp.net`, `:device_id`)
   │      ├─ Grup (`@g.us`) / Broadcast (`@broadcast`) ──► Status: QUARANTINED (group/broadcast not supported)
   │      ├─ Nomor bukan format Indonesia (`08`, `628`, `+628`) ──► Status: QUARANTINED (invalid phone)
   │      └─ Nomor valid Indonesia ──► Dinormalisasi ke E.164 (`+628...`), Status: RECEIVED
   │
   ├─► 5. Lapis 2 Deduplikasi: Persisten PostgreSQL (`whatsapp_inbound_messages`)
   │      ├─ INSERT ON CONFLICT (provider_message_id) DO NOTHING
   │      └─ Jika duplikat: HTTP 204 (X-PesenHub-Deduplicated: true) tanpa trigger event kedua
   │
   └─► 6. Hand-off ke Processing Pipeline (Issue #38 / Hermes)
          └─ Hanya pesan berstatus RECEIVED yang diteruskan ke consumer berikutnya.
```

## Kebijakan Karantina Nomor

Untuk mematuhi **Invarian #1** (Backend Golang adalah system of record) dan **Invarian #11** (Data pelanggan aman):
1. Pengirim dari grup WhatsApp atau broadcast diisolasi ke status `QUARANTINED`.
2. Pengirim dengan nomor di luar format seluler Indonesia atau format rusak diisolasi ke status `QUARANTINED`.
3. Pesan berstatus `QUARANTINED` tidak membuat record pelanggan di tabel `customers` dan tidak memicu pembuatan draft order.
4. Alasan karantina dicatat pada kolom `quarantine_reason` untuk audit dan observabilitas.

## Deduplikasi 2-Lapis

1. **Lapis 1 (In-Memory)**: Mencegah burst request ulang dari GOWA untuk request HTTP yang sama persis dalam rentang 10 menit menggunakan bounded ring (10.000 request ID).
2. **Lapis 2 (PostgreSQL Durable)**: Menggunakan constraint unik `provider_message_id` pada tabel `whatsapp_inbound_messages`. Sekalipun service di-restart atau GOWA mengirimkan ulang payload yang sama, pesan tidak diproses ganda.

## Sanitasi PII & Logging

- Nomor telepon pelanggan selalu disamarkan dalam log (`MaskPhone`: `+62812****7890`).
- Raw payload disanitasi sebelum disimpan (`payload_redacted`) untuk menjamin tidak ada token, password, atau credential yang tersimpan di database.
