# WAHA Health, Readiness, dan Webhook Security

Implementasi ini mengikuti kontrak resmi WAHA untuk [session status](https://waha.devlike.pro/docs/how-to/events/#sessionstatus) dan [HMAC webhook](https://waha.devlike.pro/docs/how-to/events/#hmac-authentication). Tidak ada pembuatan session, pairing QR, atau pengiriman pesan otomatis.

## Readiness

`GET /health/ready` membatasi seluruh pemeriksaan selama dua detik; client WAHA juga memakai `WAHA_REQUEST_TIMEOUT`. PostgreSQL yang gagal membuat readiness `not_ready` dengan HTTP 503. WAHA yang belum siap tetap menghasilkan HTTP 200 `degraded` agar operator dapat membedakan dependency opsional ini:

| Field | Nilai | Makna |
| --- | --- | --- |
| `waha_api` | `up` | WAHA menjawab request session secara valid, termasuk HTTP 404 |
| `waha_api` | `down` | Network, timeout, authentication, atau error HTTP WAHA |
| `waha_session` | `ready` | Status resmi WAHA `WORKING` |
| `waha_session` | `absent` | Session tidak ditemukan; bukan kegagalan container |
| `waha_session` | `disconnected` | Session berhenti, pairing, starting, passkey, atau failed |
| `waha_session` | `degraded` | Response/status tidak dikenali |

`waha_reason` hanya berisi kode aman seperti `timeout`, bukan URL, credential, response body, QR, atau detail session.

## Webhook HMAC

Endpoint boundary adalah `POST /webhooks/waha`. Set `WAHA_WEBHOOK_HMAC_KEY` dengan secret acak minimal 32 karakter melalui secret store, lalu gunakan nilai yang sama pada `config.webhooks[].hmac.key` ketika session development dikonfigurasi. Compose meneruskan nilai ini sebagai `WHATSAPP_HOOK_HMAC_KEY`, tetapi sengaja tidak menetapkan URL/event atau membuat session.

Request wajib membawa `X-Webhook-Request-Id`, Unix millisecond `X-Webhook-Timestamp`, `X-Webhook-Hmac-Algorithm: sha512`, dan hex `X-Webhook-Hmac` atas raw HTTP body. Verifikasi memakai perbandingan constant-time, body dibatasi 1 MiB, dan timestamp memiliki toleransi lima menit.

Request ID autentik yang berulang selama sepuluh menit diakui dengan HTTP 204 dan header `X-PesenHub-Deduplicated: true`, sehingga retry WAHA berhenti tanpa menjalankan penerimaan dua kali. Karena WAHA tidak menyediakan header nomor attempt, request ID berulang diukur sebagai duplicate sekaligus retry. Guard ini bounded (10.000 ID) dan in-memory; deduplikasi message ID durable serta pemrosesan payload dimiliki Issue #37. Restart service mengosongkan guard sementara ini.

Pada Issue #36 endpoint berhenti setelah validasi boundary dan belum menyimpan atau memproses event domain. Jangan mengaktifkan subscription event `message` pada session nyata sebelum pipeline durable Issue #37 tersedia; fixture `message` di test seluruhnya dummy.

Log hanya merekam outcome (`accepted`, `authentication_failed`, `duplicate`, dan alasan aman lain), webhook request ID valid, serta durasi. Payload, HMAC, API key, nomor telepon, nama session, dan secret tidak dicatat. Counter accepted/validation-failed/auth-failed/duplicate/retry dan total latency tersedia pada adapter untuk integrasi metrics berikutnya.

Baseline alert development: selidiki segera bila authentication failure melebihi 10 request dalam 5 menit, timeout readiness terjadi tiga kali berurutan, atau session tetap `disconnected`/`degraded` lebih dari 5 menit setelah operator mengharapkannya aktif. Duplicate/retry dipantau terhadap baseline trafik dan bukan otomatis dianggap insiden.
