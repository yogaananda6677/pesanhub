# Panduan Kontribusi PesenHub

> Setiap phase, fitur, bug, dan task wajib memiliki issue sebelum implementasi. Setiap issue dikerjakan melalui branch terpisah dan diajukan melalui Pull Request. Tidak ada perubahan langsung ke `main`.

Percakapan, `PRD.md`, atau `MEMORY.md` bukan pengganti GitHub Issue. Alur wajib untuk setiap phase dan fitur adalah:

```text
Issue → Branch → Implementasi → Pull Request → Review Owner → CI → Merge
```

## Hierarki Pekerjaan

```text
Phase Issue
├── Feature Issue
├── Feature Issue
├── Bug/Task Issue
└── Phase Closing Pull Request
```

- Setiap phase mempunyai tepat satu Phase Issue sebagai parent/tracker.
- Setiap fitur, bug, dan task teknis yang cukup besar mempunyai child issue sendiri.
- Feature Issue wajib menulis `Parent Phase: #<nomor-phase-issue>`.
- Satu issue implementasi memakai satu branch dan satu PR.
- Satu branch hanya mengerjakan satu issue utama. Satu PR hanya menutup satu issue utama, kecuali beberapa issue yang saling terkait telah disetujui Owner dan PR diberi label `policy:multi-issue-approved`.
- Phase Issue ditutup hanya oleh Phase Closing PR setelah seluruh child issue selesai, bukan secara manual atau dari Feature PR.

## Membuka Phase

Sebelum implementasi Phase N dimulai:

1. Baca `PRD.md` dan `MEMORY.md`.
2. Pastikan phase sebelumnya selesai, atau catat keputusan eksplisit Owner untuk berjalan paralel.
3. Buat Phase Issue dari template dan tuliskan seluruh exit criteria.
4. Pecah pekerjaan menjadi Feature Issue, Bug Issue, dan Task Issue.
5. Hubungkan seluruh child issue ke Phase Issue.
6. Dapatkan persetujuan Owner atas scope.
7. Assign child issue sebelum implementasi dimulai.

Feature Issue belum boleh dikerjakan jika Parent Phase belum tersedia, acceptance criteria belum jelas, belum di-assign, atau perubahan besar belum disetujui Owner.

## Branch

Setiap branch implementasi dibuat langsung dari `main` terbaru:

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/12-customer-web-order
```

Format yang diperbolehkan:

```text
phase/<issue-number>-<nama-phase>
feature/<issue-number>-<nama-fitur>
fix/<issue-number>-<nama>
docs/<issue-number>-<nama>
refactor/<issue-number>-<nama>
test/<issue-number>-<nama>
chore/<issue-number>-<nama>
```

Gunakan huruf kecil, angka, dan tanda hubung. Branch `phase/` bukan long-lived integration branch dan tidak boleh menampung implementasi beberapa fitur. Branch tersebut hanya dibuat dari `main` terbaru pada akhir phase untuk pembaruan status, checklist, `MEMORY.md`, roadmap, bukti validasi, dan penutupan Phase Issue.

Direct push dan force push ke `main` tidak diperbolehkan.

## Pull Request Implementasi

Setiap PR wajib menuju `main` dan memuat satu closing keyword untuk issue utama:

```text
Closes #12
Parent Phase: #10
```

Feature PR wajib menutup Feature Issue, mereferensikan Phase Issue yang benar, tidak menutup Phase Issue, hanya berisi scope issue, menyertakan test, lulus CI, dan memperoleh review Owner. Issue utama dan Parent Phase harus benar-benar ada; keduanya tidak boleh berupa Pull Request.

Untuk multi-issue PR yang disetujui Owner, nomor issue utama harus tetap sama dengan nomor pada branch dan setiap issue tambahan harus ditulis memakai closing keyword terpisah. Contribution Policy memvalidasi seluruh closing issue dan hanya menerima pengecualian ini setelah label `policy:multi-issue-approved` dipasang oleh Owner.

Semua PR juga wajib:

- Menjelaskan perubahan dan cara pengujian aktual.
- Menyertakan screenshot untuk perubahan UI.
- Menjelaskan migration dan rollback bila database berubah.
- Menjelaskan dampak keamanan dan privasi.
- Memperbarui `PRD.md` jika requirement berubah.
- Memperbarui `MEMORY.md` jika progres atau keputusan material berubah.
- Menyelesaikan seluruh review conversation dan tidak di-merge sendiri oleh pembuat PR.

Gunakan **Squash and merge** setelah seluruh syarat terpenuhi.

## Phase Closing Pull Request

Setelah seluruh child issue selesai, buat `phase/<phase-issue>-<nama>` dari `main` terbaru. PR ini menulis `Closes #<phase-issue>` dan hanya memuat dokumentasi penutupan: `MEMORY.md`, phase tracker/checklist, roadmap/status, bukti validasi akhir, known issue, pekerjaan tertunda, dan keputusan kesiapan phase berikutnya.

Phase Closing PR wajib mencantumkan seluruh child issue dan PR yang sudah di-merge, hasil Backend CI, Mobile CI, integration test, seluruh exit criteria, serta memperoleh review Owner dan semua required checks.

## Contoh Alur

1. Buat Phase Issue #10.
2. Buat Feature Issue #12 dengan `Parent Phase: #10`.
3. Buat branch `feature/12-customer-web-order`.
4. Implementasikan scope issue dan jalankan test.
5. Buat PR dengan `Closes #12` dan `Parent Phase: #10`.
6. Owner melakukan review.
7. Squash and merge setelah CI lulus.
8. Setelah seluruh fitur selesai, buat `phase/10-complete-phase-1`.
9. Buat Phase Closing PR dengan `Closes #10`.
10. Owner mereview dan merge setelah seluruh exit criteria lulus.

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
