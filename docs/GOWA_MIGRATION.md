# GOWA Migration — Issue #118

Issue #118 supersedes WAHA as PesenHub's active WhatsApp gateway with GOWA v9.3.0. The canonical business channel remains `WHATSAPP`; only the infrastructure adapter changes.

## Runtime contract

- Image: `aldinokemal2104/go-whatsapp-web-multidevice:v9.3.0`.
- API authentication: HTTP Basic Auth from `GOWA_BASIC_AUTH_USERNAME` and `GOWA_BASIC_AUTH_PASSWORD`.
- Device scope: `GOWA_DEVICE_ID`, sent as `X-Device-Id` on device-scoped calls.
- Readiness: public `GET /health`, followed by authenticated `GET /devices/{device_id}/status`.
- Outbound text: authenticated `POST /send/message` with `phone`, `message`, and `X-Device-Id`.
- Inbound webhook: `POST /webhooks/gowa`, signed in `X-Hub-Signature-256` as `sha256=<hex HMAC>` using `GOWA_WEBHOOK_SECRET`.
- Accepted webhook events are limited to `message,message.ack`; group JIDs are filtered by GOWA and still quarantined defensively by PesenHub.

## Data preservation

Migration 000017 renames `waha_inbound_messages` to provider-neutral `whatsapp_inbound_messages`, renames `session` to `device_id`, and adds optional `session_id`. PostgreSQL automatically retains referencing foreign keys from Hermes tables. The down migration restores the old names and retains all rows.

The old `waha_sessions` Docker volume is intentionally not deleted or reused automatically. Operators may remove it only after backup and explicit confirmation that rollback is no longer needed.

## Cutover

1. Back up PostgreSQL and the old gateway volume.
2. Configure all `GOWA_*` variables with development credentials.
3. Apply migrations and start `postgres`, `gowa`, then `api`.
4. Create/pair the approved development device manually in GOWA; never commit QR/session data.
5. Verify `/health/ready` reports `gowa_api=up` and `gowa_device=ready`.
6. Send a synthetic signed webhook and an outbound message to a test number, then verify dedupe and provider message ID persistence.

GOWA remains an unofficial WhatsApp connection and is restricted to development/pilot under the same risk controls and exit triggers originally approved for WAHA.
