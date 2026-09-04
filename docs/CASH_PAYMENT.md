# Cash Payment Recording

Issue #44 adds a backend-only command at `POST /api/v1/orders/{id}/payments/cash`.

The caller must be an authenticated `STAFF` principal and provide an `Idempotency-Key`. The JSON body contains one positive integer field, `amount`, expressed in IDR minor units. The amount must equal `orders.total_amount`; a mismatch returns `422 AMOUNT_MISMATCH` and creates no payment.

An accepted command atomically creates one `CASH` payment in `PAID` state, one immutable `payment_events` record, one redacted audit record containing the staff actor, and one transactional outbox event. It does not update `orders.status`. Repeating the same command, key, and actor returns the original payment with HTTP 200. Reusing a key with another payload or actor, or attempting a second cash payment for the order, returns `409 IDEMPOTENCY_CONFLICT`.

Rejected and cancelled orders return `409 ORDER_NOT_PAYABLE`. Cash drawer integration, refunds, and Midtrans are outside this contract.

Operational outcomes are explicit: success is `201`, duplicate retry is `200`, malformed/auth/validation/conflict failures are `400`/`403`/`422`/`409`, and a server-side timeout is bounded by the API server's 10-second read/write deadlines and returns no committed partial payment. Logs and error bodies contain request IDs but never raw authorization data.

Example request:

```http
POST /api/v1/orders/b1000000-0000-4000-8000-000000000001/payments/cash
Authorization: Bearer <staff-token>
Idempotency-Key: cash-pos-01-000042
Content-Type: application/json

{"amount":25000}
```
