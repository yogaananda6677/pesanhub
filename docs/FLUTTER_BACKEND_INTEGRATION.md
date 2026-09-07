# Flutter REST dan WebSocket Integration

Issue #48 menghubungkan antrean Flutter ke backend PesenHub tanpa mengubah aturan bisnis backend. REST tetap menjadi sumber snapshot/recovery, sedangkan WebSocket memperbarui status secara real-time.

## Konfigurasi lokal

Jangan menulis token atau password pada source, command history, Issue, PR, atau log. Buat file lokal yang sudah di-ignore:

```bash
cd pesenhub_app
cp config/runtime.example.json config/runtime.local.json
```

Isi `PESENHUB_API_BASE_URL` dan `PESENHUB_GOOGLE_SERVER_CLIENT_ID`, lalu jalankan:

```bash
flutter run --dart-define-from-file=config/runtime.local.json
```

HTTP hanya diizinkan untuk host lokal/private yang divalidasi client; host lain wajib HTTPS. Build tanpa base URL berhenti pada layar konfigurasi dan tidak dapat melewati login. Aplikasi meminta nonce backend, menjalankan Google Sign-In, lalu menukar ID token di `POST /api/v1/auth/google`. Sesi dan status approval disimpan di secure storage; database lokal, sync, order, katalog, dan WebSocket tidak dinyalakan untuk akun pending/rejected/suspended.

Backend memakai `GOOGLE_OAUTH_CLIENT_ID`, secret penandatangan `APP_SESSION_SECRET`, dan TTL maksimum 24 jam melalui `APP_SESSION_TTL`. Role dan status selalu berasal dari backend. Sesi yang sama dipakai sebagai bearer REST dan query handshake WebSocket; URL handshake tidak boleh dicatat. `APP_STAFF_TOKEN`/`APP_KDS_TOKEN` tetap diterima sementara untuk service compatibility, bukan ditanam ke build mobile.

## Alur recovery

1. Cache SQLite yang sudah dimasking ditampilkan sebagai offline/stale sementara.
2. Client memulihkan write `SYNCING` yang terputus dan flush outbox FIFO dengan idempotency key.
3. Client mengambil `GET /api/v1/orders/queue`, menyimpan snapshot secara atomik, lalu membuka WebSocket.
4. Event dengan versi lama/sama diabaikan. Versi berikutnya diterapkan sekali. Versi yang meloncat memicu snapshot ulang.
5. Disconnect memakai exponential backoff dan selalu mengambil snapshot sebelum reconnect. Penyimpanan snapshot hanya mengganti tabel queue; tabel `outbox_mutations` tidak dihapus.

Package WebSocket menangani control-frame ping/pong dari server. Status perangkat
online tidak dianggap sebagai status backend online: REST response yang berhasil
menjadi probe operasional. Gangguan memakai satu recovery worker dengan backoff
berjitter; `next_retry_at` membangunkan worker kembali walau WebSocket tetap
sehat. Kegagalan REST dipetakan menjadi state berbeda: unauthenticated,
forbidden, validation, conflict, server, network, atau invalid contract. Pesan UI
dan diagnostic state hanya menyimpan jenis kegagalan, timestamp, retry attempt,
serta `X-Request-ID`, tidak menyimpan body provider atau credential.

## Evidence deterministic

```bash
cd pesenhub_app
flutter test test/remote_api_client_test.dart
flutter test test/queue_realtime_coordinator_test.dart
flutter analyze
flutter test
```

Test membuktikan login tanpa authorization header, penyimpanan/restorasi/penghapusan sesi, mapping DTO/header/correlation ID, allowlist mutation, kebijakan retry, snapshot + event berurutan tanpa duplikasi, gap recovery, reconnect, serta outbox tetap tersimpan. Fixture seluruhnya sintetis.
