# Aturan Setup dan Menjalankan Backend PesenHub

Dokumen ini adalah panduan utama developer dan coding agent untuk setup, operasi harian, keamanan, dan troubleshooting Backend PesenHub. Source logika operasional berada pada satu script, `run.sh`; Makefile hanya menyediakan wrapper.

## Arsitektur Service

| Service | Fungsi | Host Port | Internal Address |
| --- | --- | --- | --- |
| API | Backend Golang | 8080 | `api:8080` |
| PostgreSQL | Database | dari `.env`, saat ini 55432 | `postgres:5432` |
| WAHA | WhatsApp gateway | 3000 | `waha:3000` |

API di dalam Docker wajib menggunakan `postgres:5432` dan `http://waha:3000`. Host port PostgreSQL boleh diubah melalui `POSTGRES_HOST_PORT` jika 5432 sedang dipakai, tetapi host port tidak boleh digunakan untuk koneksi antar-container. Sebelum session WhatsApp dipasangkan, container WAHA dapat sehat sementara readiness API berstatus `degraded`; kondisi ini tidak fatal pada Phase 0.

## Prasyarat

- Docker Engine dan Docker Compose plugin.
- Git dan Bash.
- Go hanya untuk test, format, pemeriksaan statis, atau development lokal.
- `curl` atau `wget` untuk health check.
- Host port 8080 dan 3000 tersedia.
- Host port PostgreSQL tersedia dan ditentukan melalui `.env`.

## Setup Pertama

```bash
cd pesenhub_be
./run.sh setup
./run.sh dev
./run.sh status
./run.sh health
```

`setup` memeriksa Docker dan Compose, memastikan file konfigurasi tersedia, lalu membuat `.env` dari `.env.example` hanya jika `.env` belum ada. File yang sudah ada tidak pernah ditimpa. Setup memvalidasi `docker compose config`, tidak mengubah port pilihan pengguna, tidak menghapus database/volume, dan tidak membuat atau memasangkan session WAHA.

Setelah `.env` dibuat pertama kali, ganti nilai `change_me` dengan credential development yang layak sebelum penggunaan nyata.

## Command Harian

| Command | Fungsi |
| --- | --- |
| `./run.sh help` | Menampilkan bantuan dan contoh. Tanpa argumen dan `--help` setara. |
| `./run.sh setup` | Memeriksa dependency, menyiapkan `.env` dengan aman, dan memvalidasi Compose. |
| `./run.sh dev` | Build lalu menjalankan stack, menunggu API/PostgreSQL, dan memeriksa health. |
| `./run.sh start` | Menjalankan stack tanpa memaksa rebuild. |
| `./run.sh build` | Membangun image API dan menampilkan ukurannya tanpa memulai service. |
| `./run.sh rebuild` | Build bersih API tanpa cache; gunakan hanya saat diperlukan. |
| `./run.sh stop` | Menghentikan container tanpa menghapus container, network, atau volume. |
| `./run.sh down` | Menghapus container dan network tanpa menghapus volume. |
| `./run.sh restart [service]` | Restart semua service atau hanya `api`, `postgres`, atau `waha`, lalu cek health. |
| `./run.sh status` | Menampilkan `docker compose ps` dan ringkasan health bila API aktif. |
| `./run.sh logs [service]` | Follow log semua/service tertentu dengan 100 baris awal. Tekan Ctrl-C untuk keluar. |
| `./run.sh health` | Menampilkan HTTP status, status API, database, dan WAHA. |
| `./run.sh test` | Menjalankan `go test ./...`. |
| `./run.sh check` | Module verify, format check, vet, test, dan validasi Compose tanpa mengubah source. |
| `./run.sh fmt` | Memperbaiki format source Go dengan `gofmt -w .`. |
| `./run.sh migrate-up` | Menjalankan seluruh migration baru melalui image API. |
| `./run.sh migrate-down [--yes]` | Rollback tepat satu migration; interaktif atau membutuhkan `--yes`. |
| `./run.sh migrate-status` | Membaca versi dan dirty state migration tanpa mutasi. |
| `./run.sh version` | Menampilkan versi tool dan seluruh image tanpa menampilkan `.env`. |

Contoh: `./run.sh logs api`, `./run.sh restart waha`, `./run.sh migrate-status`, atau `./run.sh migrate-down --yes`.

## Aturan Keamanan

- Jangan commit `.env`, API key, session/QR WAHA, data pelanggan, log sensitif, atau secret apa pun.
- Jangan mencetak password, connection string, API key, atau token ke log.
- Jangan menjalankan `docker compose down -v`, `docker volume prune`, atau `docker system prune`.
- Jangan menghapus volume PostgreSQL tanpa backup dan persetujuan eksplisit.
- Jangan memasangkan nomor WhatsApp production saat development.
- Jangan memakai data pelanggan asli untuk test.
- Jangan mengubah migration yang sudah pernah digunakan; buat migration baru.

Tidak ada command reset database, penghapusan volume, destroy, atau clean-all pada `run.sh`.

## Aturan Development

- Baca root `PRD.md` dan `MEMORY.md` sebelum mengerjakan fitur.
- Setiap fitur harus memiliki issue dan branch harus dibuat dari issue tersebut.
- Semua perubahan masuk melalui Pull Request dan Owner melakukan review sebelum merge.
- Test dan pemeriksaan relevan harus lulus sebelum PR dibuat.
- Perbarui `MEMORY.md` setelah pekerjaan material.
- Jangan mengubah status Phase menjadi `DONE` sebelum seluruh exit criteria lulus.

## Troubleshooting

### Port 5432 sedang digunakan

Ubah hanya `POSTGRES_HOST_PORT` dalam `.env`, misalnya `POSTGRES_HOST_PORT=55432`. Pertahankan `DATABASE_HOST=postgres` dan `DATABASE_PORT=5432` untuk API Docker.

### Port 8080 sedang digunakan

Hentikan proses yang tidak diperlukan atau atur host port API melalui `APP_PORT` dalam `.env`. Health script mengikuti nilai tersebut. Port container tetap 8080.

### PostgreSQL unhealthy

Jalankan `./run.sh status` dan `./run.sh logs postgres`. Periksa credential `.env`, kapasitas disk, permission volume, dan apakah data lama dibuat dengan credential berbeda. Jangan menghapus volume sebagai jalan pintas.

### API tidak dapat terhubung ke PostgreSQL

Pastikan `DATABASE_HOST=postgres`, `DATABASE_PORT=5432`, kedua service berada di network Compose yang sama, dan PostgreSQL healthy. Host port 55432 tidak digunakan API container.

### WAHA berstatus degraded

Periksa `./run.sh logs waha` dan `./run.sh health`. Jika container WAHA healthy tetapi session belum ada, readiness `degraded` memang diharapkan pada Phase 0.

### WAHA session belum dibuat

Script tidak membuat session atau pairing otomatis. Pairing hanya dilakukan sebagai pekerjaan terpisah memakai nomor development setelah persetujuan; jangan memakai nomor production.

### Migration gagal

Pastikan stack aktif, PostgreSQL healthy, image API terbaru, serta migration sebelumnya tidak dirty. Jalankan `./run.sh migrate-status` dan lihat log error tanpa menampilkan DSN. Jangan mengedit migration yang sudah diterapkan.

### Docker image gagal dibangun

Periksa koneksi registry, ruang disk, tag image di Dockerfile, dan output `./run.sh build`. Gunakan `./run.sh rebuild` hanya jika masalah memang terkait cache.

### `.env` belum tersedia

Jalankan `./run.sh setup`. Script hanya menyalin `.env.example` ketika `.env` belum ada.

### Permission denied saat menjalankan `run.sh`

Jalankan `chmod +x run.sh`, lalu ulangi `./run.sh help`. Alternatif sementara adalah `bash run.sh help`.
