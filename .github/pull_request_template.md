## Ringkasan

Jelaskan perubahan dan alasan utamanya.

## Parent Phase

Parent Phase: #

## Issue Utama

Closes #

Tambahkan closing keyword lain hanya untuk issue yang saling terkait dan telah mendapat label `policy:multi-issue-approved` dari Owner.

## Jenis Pekerjaan

- [ ] Phase closing
- [ ] Feature
- [ ] Bug fix
- [ ] Refactor
- [ ] Test
- [ ] Documentation
- [ ] Infrastructure

## Komponen Terdampak

- [ ] Backend
- [ ] Mobile
- [ ] Database
- [ ] WAHA, Hermes, atau Midtrans
- [ ] CI/CD atau dokumentasi

## Perubahan yang Dilakukan

- 

## Cara Pengujian

```text
Tuliskan command dan hasil aktual.
```

## Screenshot

Tidak berlaku / lampirkan screenshot untuk perubahan UI.

## Database Migration

Tidak ada / jelaskan migration dan rollback.

## Security and Privacy Impact

Tidak ada / jelaskan dampak dan mitigasi. Jangan menyertakan secret atau data pelanggan.

## Phase Closing Evidence

Tidak berlaku untuk PR biasa. Untuk Phase Closing PR, cantumkan seluruh child issue, PR yang sudah di-merge, hasil Backend CI, Mobile CI, integration test, exit criteria, pekerjaan tertunda, dan keputusan phase berikutnya.

## Checklist

- [ ] Phase Issue sudah tersedia.
- [ ] Feature PR mereferensikan Parent Phase.
- [ ] Branch dibuat dari `main` terbaru.
- [ ] Branch memiliki nomor issue.
- [ ] Satu branch hanya mengerjakan satu issue utama.
- [ ] PR menghubungkan satu issue utama dengan `Closes`, `Fixes`, atau `Resolves`.
- [ ] Multi-issue PR telah disetujui Owner dan memakai label `policy:multi-issue-approved`, atau tidak berlaku.
- [ ] PR tidak menutup Phase Issue kecuali ini Phase Closing PR.
- [ ] Seluruh acceptance criteria terpenuhi.
- [ ] Test sudah dijalankan dan CI relevan lulus.
- [ ] Tidak ada secret, credential, QR, session WAHA, atau data pelanggan asli.
- [ ] Dokumentasi dan `MEMORY.md` diperbarui jika diperlukan.
- [ ] Perubahan tidak keluar dari scope issue.
- [ ] Owner siap melakukan review.
