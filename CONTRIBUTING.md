# Panduan Kontribusi PesenHub

Semua perubahan mengikuti alur berikut:

```text
Buat Issue
→ Issue disetujui
→ Assign issue
→ Buat branch dari main
→ Implementasi dan test
→ Buat Pull Request
→ Owner review
→ CI lulus
→ Squash and merge
```

## Issue

Setiap fitur, bug fix, refactor, dokumentasi, testing, infrastruktur, dan maintenance wajib memiliki issue yang disetujui dan di-assign sebelum implementasi dimulai. Issue harus menjelaskan:

- Masalah atau kebutuhan dan tujuan.
- Scope serta komponen terdampak.
- Acceptance criteria yang dapat diperiksa.
- Dampak database dan migration.
- Dampak keamanan serta privasi.
- Dependensi atau blocker.

Jangan menaruh secret, session/QR WAHA, nomor telepon asli, atau data pelanggan pada issue.

## Branch

Buat branch dari `main` terbaru:

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/12-customer-order
```

Nama branch wajib cocok dengan pola:

```text
feature/<issue-number>-<nama>
fix/<issue-number>-<nama>
docs/<issue-number>-<nama>
refactor/<issue-number>-<nama>
test/<issue-number>-<nama>
chore/<issue-number>-<nama>
```

Gunakan huruf kecil, angka, dan tanda hubung, misalnya `feature/12-customer-web-order`, `fix/18-duplicate-waha-message`, atau `chore/22-backend-ci`. Direct push ke `main` tidak diperbolehkan.

## Pull Request

PR wajib:

- Mengarah ke `main` dari branch yang memuat nomor issue.
- Memuat `Closes #<nomor-issue>`, `Fixes #<nomor-issue>`, atau `Resolves #<nomor-issue>`.
- Menjelaskan perubahan, scope, dan cara pengujian.
- Menyertakan screenshot untuk perubahan UI.
- Menjelaskan migration dan rollback bila database berubah.
- Menjelaskan dampak keamanan dan privasi.
- Memperbarui `PRD.md` jika requirement berubah.
- Memperbarui `MEMORY.md` jika progres atau keputusan material berubah.
- Lulus seluruh CI dan memperoleh minimal satu review Owner.
- Menyelesaikan seluruh review conversation.
- Tidak di-merge sendiri oleh pembuat PR.

Gunakan **Squash and merge** setelah seluruh syarat terpenuhi.

## Pemeriksaan Lokal

Backend:

```bash
cd pesenhub_be
./run.sh check
```

Mobile:

```bash
cd pesenhub_app
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Jangan commit `.env`, credential, keystore, output build, log sensitif, session WAHA, atau data pelanggan.
