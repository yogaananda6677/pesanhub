# Google Owner Login dan Approval

Dokumen ini mencatat implementasi Issue #139 dan menggantikan asumsi login
username/password pada Issue #130. PesenHub tetap satu outlet. `OWNER` adalah
pengguna aplikasi operasional, sedangkan `SUPERADMIN` adalah control-plane web
yang dibangun terpisah pada Issue #140.

## Alur autentikasi

1. Mobile meminta nonce sekali pakai melalui `POST /api/v1/auth/google/challenge`.
2. Plugin resmi Google Sign-In menjalankan autentikasi platform dengan server
   client ID dan nonce tersebut.
3. Mobile mengirim hanya `id_token` dan nonce ke `POST /api/v1/auth/google`.
4. Backend memverifikasi signature melalui Google JWKS, issuer, audience,
   expiry, nonce, subject immutable, dan `email_verified`.
5. Login pertama membuat atau menghubungkan identity secara idempoten. Akun baru
   selalu `PENDING_APPROVAL`; autentikasi Google tidak pernah memberi role.
6. Backend menerbitkan sesi opaque bertanda tangan dan mencatat session ID di
   PostgreSQL. Setiap request memvalidasi expiry, revoke, role, dan status akun.

## State akses

| Status | Akses mobile |
| --- | --- |
| `PENDING_APPROVAL` | Halaman terkunci, cek status, logout |
| `APPROVED` | Capability operasional Owner |
| `REJECTED` | Halaman ditolak, cek status, logout |
| `SUSPENDED` | Halaman ditangguhkan, cek status, logout |
| Status tidak dapat diverifikasi | Fail closed; cache approved hanya boleh dipakai maksimum 2 menit |

Mobile tidak memulai SQLite operasional, sync/outbox, katalog, antrean, atau
WebSocket sebelum status efektif `APPROVED`. Endpoint bisnis tetap menolak role
status walaupun dipanggil langsung. Email pada respons mobile sudah dimasking.
Akun `SUPERADMIN` tetap diarahkan ke portal web dan tidak pernah membuka runtime
operasional mobile walaupun statusnya `APPROVED`.

## Bootstrap dan migrasi

Tidak ada password Superadmin default. Setelah migration diterapkan, operator
deployment menjalankan `go run ./cmd/bootstrap-superadmin --email <email-google>`
dari lingkungan backend terkontrol. Perintah bersifat idempoten, menolak promosi
akun Owner yang sudah ada, tidak mencetak email, dan menulis audit bootstrap.
Google subject baru diikat ketika pemilik email tersebut menyelesaikan login
Google tervalidasi. Route dan handler username/password lama sudah dihapus.
Static service token hanya tetap
ada untuk kompatibilitas integrasi internal dan tidak boleh masuk artifact mobile.

## Konfigurasi

- Backend: `GOOGLE_OAUTH_CLIENT_ID`, `APP_SESSION_SECRET`, `APP_SESSION_TTL`.
- Mobile: `PESENHUB_API_BASE_URL`, `PESENHUB_GOOGLE_SERVER_CLIENT_ID`.
- Android/iOS tetap harus didaftarkan pada Google Cloud/Firebase menggunakan
  package/bundle identifier dan signing certificate yang benar.

Token Google, nonce, bearer session, serta credential provider tidak boleh
masuk log, analytics, URL permanen, SQLite, issue, screenshot, atau repository.
