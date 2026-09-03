# Setup GitHub untuk Monorepo PesenHub

Repository aktif berada di `https://github.com/yogaananda6677/pesanhub` dengan default branch `main`. Branch protection diterapkan pada 3 September 2026 melalui Issue #10. Perubahan aturan berikutnya wajib melalui Issue dan persetujuan Owner.

## CODEOWNERS

`.github/CODEOWNERS` memetakan root, Backend, Mobile, workflow, dan dokumentasi kepada `@yogaananda6677`, yaitu akun repository Owner yang telah diverifikasi melalui GitHub CLI.

Repository masih membutuhkan minimal satu collaborator dengan akses write yang dipercaya sebagai reviewer kedua. GitHub tidak mengizinkan author menyetujui PR sendiri; jangan menurunkan aturan approval sebagai jalan pintas.

## Branch Protection `main`

Branch `main` saat ini dilindungi dengan aturan berikut:

- Require a Pull Request before merging.
- Require minimal satu approval dan approval atas push terakhir berasal dari orang selain pusher.
- Require review dari Code Owner.
- Dismiss stale approvals ketika commit baru ditambahkan.
- Require conversation resolution before merging.
- Require status checks to pass.
- Block force pushes.
- Block branch deletion.
- Terapkan aturan kepada administrator untuk mencegah bypass direct push biasa.
- Larang pembuat PR melakukan self-review; collaborator/Owner lain melakukan review dan merge.
- Gunakan **Squash and merge**.
- Require linear history dan hapus branch otomatis setelah merge.

Required checks:

```text
Contribution Policy
Backend Quality
Mobile Quality
```

Backend dan Mobile CI selalu berjalan pada PR ke `main`; bila komponennya tidak berubah, job tetap sukses dengan pesan no changes sehingga required check tidak tertahan. Merge commit dan rebase merge dinonaktifkan pada repository; hanya squash merge yang tersedia.

## Multi-Issue Pull Request

Default-nya satu branch dan PR menutup satu issue utama. Beberapa issue yang benar-benar saling terkait hanya boleh digabung setelah persetujuan Owner dan pemberian label PR berikut:

```text
policy:multi-issue-approved
```

Nomor issue utama harus sama dengan nomor branch. Semua issue tambahan tetap ditulis dengan closing keyword sendiri. Contribution Policy memeriksa bahwa seluruh nomor benar-benar Issue dan bukan Pull Request.

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

Inventaris environment, owner, source/provision, serta rotasi tersedia di [`ENVIRONMENT.md`](ENVIRONMENT.md).
