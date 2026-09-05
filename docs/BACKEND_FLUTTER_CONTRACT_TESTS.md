# Backend–Flutter Contract Gate

Issue #49 menambahkan compatibility gate untuk mendeteksi breaking change REST/WebSocket sebelum merge. Gate ini melengkapi integration/E2E test; bukan penggantinya.

## Sumber canonical

`contracts/backend_flutter_v1.json` adalah satu-satunya fixture lintas komponen. File ini dihasilkan secara deterministik oleh `pesenhub_be/cmd/contractfixture` dari tipe provider Go yang benar-benar dipakai backend: order detail/collection, pagination, payment, error envelope, dan order event. Enum source, order status, payment method/status berasal dari `internal/domain`.

Jangan mengedit fixture secara manual. Setelah perubahan kontrak backend yang memang disetujui:

```bash
cd pesenhub_be
go run ./cmd/contractfixture -write ../contracts/backend_flutter_v1.json
go run ./cmd/contractfixture -check ../contracts/backend_flutter_v1.json
```

Flutter membaca file yang sama dari `test/backend_contract_test.dart`. Test melakukan deserialisasi melalui DTO production dan assertion semantik, bukan snapshot seluruh JSON.

## Cakupan compatibility

- Queue REST dan order collection: required fields, source, status, monetary integer, nested item, version, serta timestamp.
- Pagination: `size` 1–100 dan `next_cursor` string/null.
- Payment: method/status, amount integer positif, version, dan timestamp.
- Error envelope: HTTP status, code, message, safe field details, serta kecocokan body/header `X-Request-ID` dengan typed failure Flutter.
- WebSocket event: event type, order/status, version, serta korelasi nilai envelope dengan payload.
- Privacy: fixture hanya berisi identitas sintetis, nomor termasking, dan tidak memuat bearer token atau credential.

Negative tests sengaja mengganti nama required field, mengubah integer menjadi string, dan menghapus event ID. Semuanya harus ditolak consumer. Di sisi provider, perubahan JSON tag/type mengubah output generator sehingga pemeriksaan stale fixture gagal.

## Kebijakan perubahan

1. Perubahan additive optional boleh dilakukan dengan memperbarui provider, fixture, OpenAPI, dan consumer bila dibutuhkan.
2. Rename, penghapusan required field, perubahan tipe, atau pengurangan enum dianggap breaking. Buat issue kontrak terpisah, tentukan strategi versioning/migrasi, dan update backend serta Flutter dalam PR yang disetujui.
3. Fixture hanya boleh diregenerasi setelah perubahan provider disengaja; jangan meregenerasi hanya untuk membuat CI hijau.
4. Bila gate gagal, catat nama schema/field, expected versus actual, commit/PR, dan command reproduksi. Jangan menempelkan token, nomor pelanggan asli, atau raw provider response.

## CI dan reproduksi

Perubahan pada `contracts/**` memicu Backend Quality dan Mobile Quality. Backend menjalankan stale check eksplisit; Mobile menjalankan contract test eksplisit sebelum suite penuh.

```bash
cd pesenhub_be
go run ./cmd/contractfixture -check ../contracts/backend_flutter_v1.json
go test ./internal/contractfixture

cd ../pesenhub_app
flutter test test/backend_contract_test.dart
```

Jika stale check gagal, lihat diff hasil generator sebelum memutuskan regenerasi. Jika consumer test gagal, perbaiki DTO atau batalkan breaking provider change. Failure yang tidak dapat diperbaiki dalam scope harus menjadi remediation issue dengan evidence aman, bukan checklist yang dipaksakan lulus.
