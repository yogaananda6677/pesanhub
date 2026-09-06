# Flutter REST dan WebSocket Integration

Issue #48 menghubungkan antrean Flutter ke backend PesenHub tanpa mengubah aturan bisnis backend. REST tetap menjadi sumber snapshot/recovery, sedangkan WebSocket memperbarui status secara real-time.

## Konfigurasi lokal

Jangan menulis token atau password pada source, command history, Issue, PR, atau log. Buat file lokal yang sudah di-ignore:

```bash
cd pesenhub_app
cp config/runtime.example.json config/runtime.local.json
```

Isi hanya `PESENHUB_API_BASE_URL` dengan endpoint backend, lalu jalankan:

```bash
flutter run --dart-define-from-file=config/runtime.local.json
```

HTTP hanya diizinkan untuk `localhost`, `127.0.0.1`, dan alamat emulator Android `10.0.2.2`; host lain wajib HTTPS. Build tanpa base URL berhenti pada layar konfigurasi dan tidak dapat melewati login. Aplikasi meminta username dan password akun outlet tunggal melalui `POST /api/v1/auth/login`, lalu menyimpan sesi kedaluwarsa di secure storage platform. Tidak ada pemilih role Owner/Operator/Kasir; capability `STAFF` hanya detail internal backend.

Backend memakai `APP_LOGIN_USERNAME`, hash bcrypt `APP_LOGIN_PASSWORD_HASH`, secret penandatangan `APP_SESSION_SECRET`, dan TTL maksimum 24 jam melalui `APP_SESSION_TTL`. Password plaintext tidak disimpan. Sesi yang sama dipakai sebagai bearer REST dan query handshake WebSocket; URL handshake tidak boleh dicatat. `APP_STAFF_TOKEN`/`APP_KDS_TOKEN` tetap diterima sementara untuk service compatibility, bukan ditanam ke build mobile.

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
