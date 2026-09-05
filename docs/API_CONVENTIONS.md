# PesenHub HTTP API Conventions

Status: accepted for Phase 1A through Issue #13. The machine-readable contract is [`openapi.yaml`](api/openapi.yaml).

Compatibility REST/WebSocket dengan Flutter dijaga oleh fixture canonical dan
gate CI yang dijelaskan di
[`BACKEND_FLUTTER_CONTRACT_TESTS.md`](BACKEND_FLUTTER_CONTRACT_TESTS.md).

## Versioning and Compatibility

- Business endpoints use `/api/v1`; operational `/health/*` endpoints remain unversioned.
- Additive optional fields and new enum values may ship within v1. Clients must ignore unknown response fields and handle unknown enum values safely.
- Removing/renaming fields, changing meaning/type, or making optional input required needs a new major base path and migration window.
- JSON field names use `snake_case`; timestamps use RFC 3339 UTC; IDs are opaque strings.

## Request and Response

- JSON content type is `application/json; charset=utf-8`.
- Clients may send `X-Request-ID` using 1–128 letters, digits, `.`, `_`, or `-`; invalid/missing values are replaced. Every response echoes the effective ID.
- Success returns the resource directly for single resources. Collections use `data` and `page` metadata.
- `204 No Content` has no response body.

Error response:

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Request validation failed.",
    "details": [{"field": "name", "reason": "required"}],
    "request_id": "req-example-1"
  }
}
```

`code` is stable and machine-readable. `message` is safe for users. Validation `details` may contain only public field paths and reason codes—never submitted values, secrets, stack traces, SQL/provider errors, or other PII.

## Pagination, Filter, and Sort

- Cursor pagination: `page[size]` defaults to 20 and accepts 1–100; `page[cursor]` is an opaque base64url token.
- Response `page.next_cursor` is `null` at the end and `page.size` is the applied size.
- Filters use `filter[field]=value`. Each endpoint documents an allowlist; unknown filters return `400 INVALID_QUERY`.
- Sort uses `sort=field` or `sort=-field`. Each endpoint has an allowlist and default.
- Database ordering must append immutable `id` in the same direction as a deterministic tie-breaker. Cursor payload is server-owned and must bind the active sort/filter context.

## Mutation Contract

- Protected mutations require `Authorization: Bearer <token>`; missing/invalid credentials return `401`, insufficient permission returns `403`.
- JSON is decoded strictly: malformed bodies and unknown fields return `400`; semantic field errors return `422` with safe `details`.
- Creation and command endpoints that can be retried require `Idempotency-Key` (1–128 printable non-whitespace characters). The same actor, route, key, and canonical payload replay the original status/body; the same key with a different payload returns `409 IDEMPOTENCY_CONFLICT`.
- Updates use an expected version in the documented request field or `If-Match`. A stale version returns `409 VERSION_CONFLICT` and must not partially mutate state.
- Persistence, audit, and outbox writes succeed atomically before a success response.

## Status Codes

| Status | Use |
| --- | --- |
| 200 | Successful read/update/command with body |
| 201 | Resource created; include `Location` |
| 204 | Successful delete/command without body |
| 400 | Malformed JSON or invalid query/header syntax |
| 401/403 | Authentication missing/invalid or permission denied |
| 404 | Resource absent or intentionally hidden |
| 409 | Version, state transition, or idempotency conflict |
| 422 | Well-formed request with field validation failure |
| 429 | Rate limited; include `Retry-After` |
| 500 | Unexpected internal error with redacted message |
| 503 | Dependency unavailable; retry only when operation semantics allow it |

## Testable Examples

Success collection: `GET /api/v1/examples?page[size]=20&sort=-created_at` returns `200`, an array under `data`, page size 20, and deterministic ordering by `created_at DESC, id DESC`.

Invalid input: `GET /api/v1/examples?page[size]=101` returns `400 INVALID_QUERY`. A create request missing `name` returns `422 VALIDATION_FAILED` with `details=[{"field":"name","reason":"required"}]`. Both include the effective `request_id`.
