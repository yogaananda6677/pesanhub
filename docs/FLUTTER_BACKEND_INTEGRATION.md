# Flutter REST dan WebSocket Integration

Issue #48 menghubungkan antrean Flutter ke backend PesenHub tanpa mengubah aturan bisnis backend. REST tetap menjadi sumber snapshot/recovery, sedangkan WebSocket memperbarui status secara real-time.

## Konfigurasi lokal

Jangan menulis token pada source, command history, Issue, PR, atau log. Buat file lokal yang sudah di-ignore:

```bash
cd pesenhub_app
cp config/runtime.example.json config/runtime.local.json
```

Isi `PESENHUB_API_BASE_URL` dan `PESENHUB_API_TOKEN` dengan endpoint serta token `APP_STAFF_TOKEN` development, lalu jalankan:

```bash
flutter run --dart-define-from-file=config/runtime.local.json
```

Kedua nilai wajib tersedia bersama. HTTP hanya diizinkan untuk `localhost`, `127.0.0.1`, dan alamat emulator Android `10.0.2.2`; host lain wajib HTTPS. Build tanpa keduanya tetap membuka showcase data sintetis. Token dari `dart-define` tertanam dalam artifact, sehingga artifact development diperlakukan sebagai secret-adjacent, tidak dibagikan publik, dan token wajib dirotasi. Login/runtime credential store production berada di luar scope pilot ini.

Backend memakai `APP_STAFF_TOKEN` dan `APP_KDS_TOKEN` yang berbeda dengan minimum 32 karakter. REST mengirim `Authorization: Bearer ...`; handshake WebSocket browser memakai query `token` karena WebSocket API browser tidak mendukung custom header. URL handshake tidak boleh dicatat atau dimasukkan ke evidence.

## Alur recovery

1. Cache SQLite yang sudah dimasking ditampilkan sebagai offline/stale sementara.
2. Client mengambil `GET /api/v1/orders/queue`, menyimpan snapshot secara atomik, lalu mencoba flush outbox FIFO dengan idempotency key.
3. Bila outbox berubah di server, snapshot diambil ulang sebelum WebSocket terhubung.
4. Event dengan versi lama/sama diabaikan. Versi berikutnya diterapkan sekali. Versi yang meloncat memicu snapshot ulang.
5. Disconnect memakai exponential backoff dan selalu mengambil snapshot sebelum reconnect. Penyimpanan snapshot hanya mengganti tabel queue; tabel `outbox_mutations` tidak dihapus.

Package WebSocket menangani control-frame ping/pong dari server. Kegagalan REST dipetakan menjadi state berbeda: unauthenticated, forbidden, validation, conflict, server, network, atau invalid contract. Pesan UI dan diagnostic state hanya menyimpan jenis kegagalan serta `X-Request-ID`, tidak menyimpan body provider atau credential.

## Evidence deterministic

```bash
cd pesenhub_app
flutter test test/remote_api_client_test.dart
flutter test test/queue_realtime_coordinator_test.dart
flutter analyze
flutter test
```

Test membuktikan mapping DTO/header/correlation ID, allowlist mutation, kebijakan retry, snapshot + event berurutan tanpa duplikasi, gap recovery, reconnect, serta outbox tetap tersimpan. Fixture seluruhnya sintetis.
