# Customer Identity and Privacy

- Indonesian mobile inputs `08…`, `628…`, `+628…`, and bare `8…` normalize to one E.164 `+628…` value. Only mobile NSNs beginning with `8` and 9–12 digits are accepted.
- Customer IDs are internal UUIDs. A unique phone identifies a candidate profile but is not proof of identity.
- Create requires `Idempotency-Key`. An equivalent retry returns the existing profile; a different name/preferences using an existing phone or key returns `PHONE_PROFILE_CONFLICT` for explicit staff resolution. Profiles are never auto-merged.
- Update uses expected `version`. Stale writes return `VERSION_CONFLICT`.
- Profile/history access requires a staff principal or a verified customer principal whose `customer_id` matches the path. Supplying or guessing a phone/UUID alone grants nothing.
- Auth/OTP production is outside #15. Until an authentication middleware injects a principal, protected runtime routes default to `FORBIDDEN`.
- Logs and errors must not contain raw phone, submitted preferences, or database/provider details. Orders retain identity snapshots so profile correction does not rewrite history.
