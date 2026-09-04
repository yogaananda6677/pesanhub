# Environment Development dan Secret Matrix

Dokumen ini adalah sumber operasional lintas komponen untuk Issue #12. Nilai secret tidak boleh disimpan pada repository, Issue, Pull Request, log, screenshot, atau artifact publik.

## Prasyarat

| Komponen | Versi/acuan | Kegunaan |
| --- | --- | --- |
| Git dan GitHub CLI | Versi yang masih didukung | Workflow Issue, branch, PR, dan review |
| Docker Engine + Compose | Compose plugin | Menjalankan API, PostgreSQL, dan WAHA |
| Go | Mengikuti `pesenhub_be/go.mod` | Test, vet, format, dan development Backend |
| Flutter | `3.44.4` stable | Build/test aplikasi kasir dan KDS |
| Dart | Mengikuti Flutter; constraint project `^3.12.2` | Analyze, format, dan test |
| Java | Temurin 17 pada CI | Build Android |

Versi image Backend yang tervalidasi tercatat pada `pesenhub_be/REQUIREMENTS.md`. Jangan meng-upgrade tool/image sebagai bagian setup tanpa Issue dan PR terpisah.

## Setup Backend

```bash
cd pesenhub_be
./run.sh setup
./run.sh dev
./run.sh status
./run.sh health
./run.sh check
```

`setup` membuat `.env` dari `.env.example` hanya jika file belum ada. File `.env` yang ada tidak ditimpa. Jangan memakai `docker compose down -v`, menghapus volume, atau memasangkan nomor WhatsApp production.

Expected result development:

- PostgreSQL dan container WAHA sehat.
- API live dan database ready.
- API boleh melaporkan `degraded` ketika session WAHA development belum dibuat.
- `./run.sh check` menyelesaikan module verification, format check, vet, unit test, dan Compose validation.

## Setup Mobile

```bash
cd pesenhub_app
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

APK development tidak memerlukan production keystore. `android/local.properties`, `key.properties`, `*.jks`, dan `*.keystore` harus tetap di-ignore.

## Backend Environment Matrix

Semua nama berikut berasal dari `pesenhub_be/.env.example`, config Go, atau Docker Compose. Kolom source menjelaskan tempat nilai diperoleh—bukan nilai aktualnya.

| Variable | Kategori | Scope | Source/provision | Owner | Rotasi |
| --- | --- | --- | --- | --- | --- |
| `APP_NAME` | Public config | API | `.env.example` / deployment config | Backend Owner | Saat branding berubah |
| `APP_ENV` | Public config | API | Environment config | Backend/DevOps Owner | Saat environment berubah |
| `APP_HOST` | Public config | API | Environment config | DevOps Owner | Sesuai topology |
| `APP_PORT` | Public config | Host/API | Environment config | DevOps Owner | Saat port conflict/topology berubah |
| `APP_TIMEZONE` | Public config | Domain display/schedule | Keputusan outlet | Product/Backend Owner | Saat timezone outlet berubah |
| `DATABASE_HOST` | Sensitive config | API → PostgreSQL | Compose/service discovery atau secret platform | DevOps Owner | Saat endpoint berubah |
| `DATABASE_PORT` | Sensitive config | API → PostgreSQL | Compose/service discovery | DevOps Owner | Saat endpoint berubah |
| `POSTGRES_HOST_PORT` | Local config | Host → PostgreSQL | Developer `.env` | Developer | Saat port host conflict |
| `DATABASE_NAME` | Sensitive config | API/PostgreSQL | Secret/deployment platform | Database Owner | Saat provision ulang |
| `DATABASE_USER` | Secret-adjacent identity | API/PostgreSQL | Secret/deployment platform | Database Owner | Saat credential rotation |
| `DATABASE_PASSWORD` | Secret | API/PostgreSQL | Password generator + secret store | Database/DevOps Owner | Berkala dan setelah suspected exposure |
| `DATABASE_SSLMODE` | Security config | API → PostgreSQL | Deployment policy | Security/DevOps Owner | Saat topology/TLS berubah |
| `WAHA_BASE_URL` | Sensitive config | API → WAHA | Compose/service discovery | DevOps Owner | Saat endpoint berubah |
| `WAHA_API_KEY` | Secret | API/WAHA | Generator + secret store | WhatsApp/DevOps Owner | Berkala dan setelah suspected exposure |
| `WAHA_SESSION` | Sensitive identifier | API/WAHA | Session development yang disetujui | WhatsApp Owner | Saat session diganti/revoked |
| `WAHA_REQUEST_TIMEOUT` | Public config | API | `.env.example` / deployment config | Backend Owner | Berdasarkan latency evidence |
| `WAHA_WEBHOOK_HMAC_KEY` | Secret | API/WAHA webhook | Generator + secret store | WhatsApp/DevOps Owner | Berkala dan setelah suspected exposure |
| `WAHA_DASHBOARD_USERNAME` | Secret-adjacent identity | WAHA dashboard | Secret store | WhatsApp/DevOps Owner | Bersama dashboard credential |
| `WAHA_DASHBOARD_PASSWORD` | Secret | WAHA dashboard | Password generator + secret store | WhatsApp/DevOps Owner | Berkala dan setelah suspected exposure |

`DATABASE_HOST=postgres`, `DATABASE_PORT=5432`, dan `WAHA_BASE_URL=http://waha:3000` adalah alamat antar-container development. Nilai host-side berbeda bila API dijalankan langsung; ikuti `pesenhub_be/REQUIREMENTS.md` dan jangan mengubah default repository hanya karena port lokal bentrok.

## CI/CD dan Future Secret Matrix

| Secret/config | Status | Scope | Provision/storage | Owner | Rotasi |
| --- | --- | --- | --- | --- | --- |
| `GITHUB_TOKEN` | Aktif, otomatis | GitHub Actions/GHCR | Disediakan per-run oleh GitHub; permission minimum | Repository Owner | Otomatis per-run |
| `ANDROID_KEYSTORE_BASE64` | Belum diaktifkan | Android production signing | GitHub Environment secret dari keystore production | Mobile/Release Owner | Saat key diganti/compromised |
| `ANDROID_KEYSTORE_PASSWORD` | Belum diaktifkan | Android signing | GitHub Environment secret | Mobile/Release Owner | Bersama keystore |
| `ANDROID_KEY_ALIAS` | Belum diaktifkan | Android signing | GitHub Environment secret/config | Mobile/Release Owner | Saat key diganti |
| `ANDROID_KEY_PASSWORD` | Belum diaktifkan | Android signing | GitHub Environment secret | Mobile/Release Owner | Bersama key |
| Midtrans server/client credential | Belum diimplementasikan | Backend payment sandbox/production | Secret store terpisah per environment; nama variable ditentukan pada #45 | Payment/DevOps Owner | Sesuai provider dan setelah exposure |
| Hermes provider credential/model config | Belum diimplementasikan | Backend agent | Secret store terpisah per environment; nama variable ditentukan pada #38 | Agent/DevOps Owner | Sesuai provider dan setelah exposure |

Jangan membuat nama environment variable Midtrans/Hermes seolah sudah menjadi kontrak sebelum Issue implementasinya disetujui. Sandbox dan production harus memakai credential serta GitHub Environment yang terpisah.

## Kebijakan Environment

- Local: data sintetis, credential development unik per developer, tanpa session/nomor WhatsApp production.
- CI: service ephemeral atau mock; tidak pairing WAHA dan tidak mengirim pesan/transaksi nyata.
- Sandbox: akun/provider sandbox khusus; batasi akses dan redaksi artifact/log.
- Production: secret manager atau GitHub Environment dengan approval, least privilege, audit, dan rotasi.
- Tidak boleh menyalin database production ke development. Fixture memakai nama dan nomor sintetis.
- Secret yang diduga bocor harus direvoke/rotate lebih dahulu, lalu artifact/log/history diaudit. Jangan sekadar menghapus baris terbaru.

## Verifikasi Tanpa Membocorkan Nilai

```bash
git ls-files | rg '(^|/)(\.env$|local\.properties$|.*\.jks$|.*\.keystore$)'
cd pesenhub_be && docker compose config --quiet
cd ../pesenhub_app && flutter analyze && flutter test
```

Expected result command pertama adalah tidak ada secret file tracked. `.env.example` memang boleh tracked karena hanya berisi placeholder development dan tetap harus diperiksa sebelum perubahan.

## Troubleshooting Aman

- Missing variable: bandingkan nama key dengan `.env.example`; jangan meminta nilai secret melalui Issue/PR/chat publik.
- Credential invalid: periksa source/owner secret dan lakukan rotasi bila perlu; jangan mencetak nilainya.
- Port conflict: ubah host mapping lokal yang didukung, bukan alamat antar-container.
- WAHA degraded: periksa health/log yang sudah disamarkan; jangan membuat pairing production sebagai jalan pintas.
- Build Android meminta keystore: gunakan debug build sampai signing production dikerjakan dalam Issue release tersendiri.
