# Setup GitHub untuk Monorepo PesenHub

Konfigurasi lokal sudah siap dipush, tetapi repository GitHub, remote, username Owner, dan branch protection belum dibuat. Setelah repository tersedia, tambahkan remote dan push hanya dengan persetujuan pemilik proyek.

## CODEOWNERS

1. Ganti `USERNAME_OWNER` pada `.github/CODEOWNERS.example` dengan username atau team GitHub yang benar.
2. Rename file menjadi `.github/CODEOWNERS`.
3. Ajukan perubahan melalui Issue dan Pull Request.

Jangan memakai placeholder sebagai CODEOWNERS aktif karena akan membuat review ownership tidak valid.

## Branch Protection `main`

Di GitHub, buka **Settings → Branches** atau **Rules → Rulesets**, lalu lindungi branch `main` dengan aturan berikut:

- Require a Pull Request before merging.
- Require minimal satu approval.
- Require review dari Code Owner.
- Dismiss stale approvals ketika commit baru ditambahkan.
- Require conversation resolution before merging.
- Require status checks to pass.
- Block force pushes.
- Block branch deletion.
- Batasi direct push ke `main`.
- Larang pembuat PR melakukan self-merge; Owner lain melakukan review dan merge.
- Gunakan **Squash and merge**.

Required checks:

```text
Contribution Policy
Backend Quality
Mobile Quality
```

Aktifkan branch protection setelah workflow pernah dijalankan setidaknya sekali agar nama check tersedia di GitHub. Backend dan Mobile CI selalu berjalan pada PR ke `main`; bila komponennya tidak berubah, job tetap sukses dengan pesan no changes sehingga required check tidak tertahan.

## Secrets dan Signing Mobile

Backend CD memakai `GITHUB_TOKEN` bawaan dengan permission `packages: write` untuk GHCR. Tidak ada deployment server.

Mobile CD menghasilkan artifact APK release untuk pengujian internal, bukan APK production-signed dan tidak mengunggah ke Play Store. Signing production di masa depan membutuhkan secret berikut dan harus dikerjakan dalam issue terpisah:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

Jangan menaruh nilai secret tersebut di repository, issue, PR, log, atau artifact publik.
