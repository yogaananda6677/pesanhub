# GOWA Health, Device Readiness, and Webhook Security

PesenHub targets GOWA v9.3.0 and follows its official `/health`, `/devices/{device_id}/status`, and webhook contracts. The backend never creates a device or initiates pairing automatically.

`GET /health/ready` checks GOWA with a bounded `GOWA_REQUEST_TIMEOUT`. PostgreSQL failure returns HTTP 503. A healthy GOWA API with no connected/logged-in device returns HTTP 200 `degraded`:

| Field | Values | Meaning |
| --- | --- | --- |
| `gowa_api` | `up`, `down` | Public `/health` and authenticated device-status API availability |
| `gowa_device` | `ready`, `absent`, `disconnected`, `degraded`, `unknown` | Configured device connection state |
| `gowa_reason` | safe code | `timeout`, `authentication_failed`, `device_not_found`, etc. |

Outbound requests use HTTP Basic Auth and `X-Device-Id`. Text messages are sent to `POST /send/message` with `phone` as an `@s.whatsapp.net` JID and `message` as text. Credentials, full JIDs, and response bodies are never added to health responses or error logs.

GOWA sends webhooks to `POST /webhooks/gowa`. Configure the same minimum-32-character secret in `GOWA_WEBHOOK_SECRET` and GOWA `WHATSAPP_WEBHOOK_SECRET`. PesenHub verifies the raw body using constant-time HMAC-SHA256 against `X-Hub-Signature-256: sha256=<hex>`, limits bodies to 1 MiB, and rejects malformed or invalid signatures.

GOWA does not provide the timestamp/request-ID proof previously used by WAHA. PesenHub therefore uses a bounded raw-body hash replay guard for burst retries and PostgreSQL `provider_message_id` uniqueness for durable deduplication. Only `message` events are ingested. `is_from_me` messages are ignored; groups and unsupported senders are quarantined. The top-level `device_id` is required and `session_id` is retained when supplied.

Compose disables the optional UI and MCP endpoint, disables automatic media downloads, filters webhook events, ignores group JIDs before delivery, and persists `/app/storages`. Pair only a dedicated development/pilot number and never commit its storage, QR code, credentials, or customer payloads.
