# Login dan Sesi Aplikasi Outlet Tunggal

Dokumen ini mencatat keputusan Issue #130. PesenHub adalah satu aplikasi untuk satu outlet, bukan produk multi-tenant dengan pemilihan persona. Karena itu layar login hanya menerima username dan kata sandi; istilah Owner, Operator, dan pemilih role tidak ditampilkan. Backend tetap menggunakan capability internal `STAFF` untuk otorisasi endpoint yang sudah ada.

## Kontrak dan alur

1. Mobile dibangun hanya dengan `PESENHUB_API_BASE_URL`; tidak ada credential dalam `dart-define` atau artifact.
2. `POST /api/v1/auth/login` menerima JSON `username` dan `password`, maksimal 4 KiB dan tanpa field tambahan.
3. Backend membandingkan username secara constant-time dan password dengan bcrypt. Respons kegagalan selalu generik agar keberadaan username tidak bocor.
4. Login sukses mengembalikan opaque HMAC-SHA256 session, tipe `Bearer`, dan `expires_at`. TTL default 8 jam dan dibatasi maksimum 24 jam.
5. Mobile menyimpan token serta expiry di secure storage platform, memulihkannya pada cold start, dan memakai sesi yang sama pada REST serta WebSocket.
6. Logout menghapus secure storage dan menghentikan coordinator WebSocket. Sesi kedaluwarsa dihapus dan pengguna kembali ke login.

Backend membatasi lima percobaan per alamat client dalam jendela satu menit dan mengembalikan `429` + `Retry-After`. Request ID tetap tersedia, sedangkan password, hash, token, body login, dan URL WebSocket tidak boleh masuk log.

## Konfigurasi

- `APP_LOGIN_USERNAME`: identitas akun outlet tunggal.
- `APP_LOGIN_PASSWORD_HASH`: bcrypt hash, bukan password plaintext. Prefix `base64:` dapat dipakai untuk encoding hash agar karakter `$` portabel di Docker/Compose; hasil decode tetap wajib bcrypt valid.
- `APP_SESSION_SECRET`: random secret minimum 32 karakter untuk HMAC.
- `APP_SESSION_TTL`: masa sesi positif, maksimum 24 jam.

Nilai `.env.example` hanya credential development dan wajib diganti sebelum deployment. Buat bcrypt hash baru secara lokal, simpan hasilnya di secret store, dan jangan kirim password/hash melalui Issue atau PR.

`APP_STAFF_TOKEN` dan `APP_KDS_TOKEN` masih diverifikasi secara exact untuk kompatibilitas integrasi non-mobile. Jalur ini bersifat transisi dan tidak boleh dipakai kembali sebagai konfigurasi build Flutter.

## Verifikasi

```bash
cd pesenhub_be
go test ./internal/appauth ./internal/customer ./internal/config

cd ../pesenhub_app
flutter test test/session_test.dart test/remote_api_client_test.dart test/queue_realtime_coordinator_test.dart
flutter analyze
```

Test mencakup token valid/tampered/expired, konfigurasi lemah, kredensial salah, body ketat, rate limit, kontrak login mobile, restore/logout, dan ketiadaan pemilih persona.
