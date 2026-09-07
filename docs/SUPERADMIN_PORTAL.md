# PesenHub Superadmin Portal & Control Plane

## 1. Ringkasan & Arsitektur

Portal Superadmin adalah kontrol plane berbasis web (**Web Only**) yang dirancang untuk mengelola approval akun pengguna (Owner), siklus hidup akun, serta memantau kesehatan infrastruktur dan telemetri sistem secara real-time.

```
+-------------------------------------------------------------------------+
|                        PesenHub Web Control Plane                       |
|                          (http://.../superadmin/)                       |
+-------------------------------------------------------------------------+
                                    |
                                    | HTTPS / Bearer Token (Role: SUPERADMIN)
                                    v
+-------------------------------------------------------------------------+
|                          PesenHub Backend API                           |
|  +-----------------------------+     +-------------------------------+  |
|  | Superadmin Control Plane    |     | Operational Outlet API        |  |
|  | - /superadmin/health/*      |     | - /orders, /menu, /customers  |  |
|  | - /superadmin/telemetry/*   |     | - /payments, /agent/*         |  |
|  | - /superadmin/users/*       |     | (SUPERADMIN: STRICTLY FORBID) |  |
|  | - /superadmin/audits        |     | (OWNER / STAFF ONLY)          |  |
|  +-----------------------------+     +-------------------------------+  |
+-------------------------------------------------------------------------+
       |                  |                    |                  |
       v                  v                    v                  v
+--------------+   +--------------+     +--------------+   +--------------+
|  PostgreSQL  |   | GOWA Service |     | WebSocket    |   | Outbox       |
|  (App DB)    |   | (WhatsApp)   |     | Hub          |   | Workers      |
+--------------+   +--------------+     +--------------+   +--------------+
```

### Prinsip Isolasi & Keamanan Ketat
1. **Web Only**: Portal Superadmin hanya tersedia melalui peramban web pada path `/superadmin/`. Tidak ada rute, tampilan, dependensi, maupun kapabilitas Superadmin pada aplikasi mobile Flutter (`pesenhub_app/`).
2. **Zero Operational Access (Separation of Duties)**:
   - Superadmin **DILARANG KERAS** mengakses atau mengoperasikan fungsi operasional kasir, dapur (KDS), pesanan, katalog menu, pembayaran, chat pelanggan Hermes WhatsApp, maupun data transaksi harian.
   - Seluruh endpoint operasional (`/api/v1/orders/*`, `/api/v1/admin/*`, `/api/v1/customers/*`, `/api/v1/payments/*`) menerapkan otorisasi ketat berbasis `customer.CanOperateOutlet(p)` yang hanya mengizinkan `STAFF` dan `OWNER`. Role `SUPERADMIN` secara otomatis ditolak dengan HTTP 403 Forbidden.
3. **Perlindungan Privasi & PII**:
   - Seluruh alamat email pengguna dimasker sebelum disajikan ke web (`yo***@example.com`).
   - Nomor telepon pelanggan atau token rahasia tidak pernah ditampilkan pada portal Superadmin.
4. **Audit Trail Imutabel**:
   - Setiap mutasi status akun (`APPROVE`, `REJECT`, `SUSPEND`, `REACTIVATE`) dan pencabutan sesi dicatat ke tabel `user_status_audits` lengkap dengan actor ID, masked email, alasan/catatan kebijakan, dan Request ID pelacak.

---

## 2. Siklus Hidup Pengguna & State Machine

Status akun pada PesenHub mengikuti transisi terdefinisi berikut:

```
                  +--------------------------------+
                  |  UNDANGAN (INVITED)           |
                  |  Pre-approved email oleh SA    |
                  +--------------------------------+
                                  |
                                  | Google Sign-In pertama
                                  v
                  +--------------------------------+
                  |  PENDING_APPROVAL              |
                  |  Akun dibuat, menunggu review  |
                  +--------------------------------+
                     /                          \
     Setujui (SA)   /                            \   Tolak (SA)
                   v                              v
+------------------------+              +------------------------+
|  APPROVED              |              |  REJECTED              |
|  Akses penuh mobile    |              |  Akses ditolak         |
+------------------------+              +------------------------+
   |                  ^                           |
   | Suspend (SA)     | Aktifkan kembali (SA)     | Aktifkan kembali (SA)
   v                  |                           |
+------------------------+                        |
|  SUSPENDED             | <----------------------+
|  Sesi dicabut seketika |
+------------------------+
```

### Aturan Transisi:
- **INVITED -> PENDING_APPROVAL**: Dibuat melalui endpoint `POST /api/v1/superadmin/users/invite`. Saat pengguna login dengan Google menggunakan email yang sesuai, status otomatis menjadi `PENDING_APPROVAL` (atau `APPROVED` jika sistem auto-approval diaktifkan).
- **PENDING_APPROVAL -> APPROVED**: Superadmin menyetujui akun melalui `POST /api/v1/superadmin/users/{id}/approve`. Pengguna langsung dapat login dan mengelola outlet.
- **PENDING_APPROVAL -> REJECTED**: Superadmin menolak pendaftaran melalui `POST /api/v1/superadmin/users/{id}/reject`.
- **APPROVED -> SUSPENDED**: Superadmin menangguhkan akun melalui `POST /api/v1/superadmin/users/{id}/suspend`. **Semua sesi aktif di `app_sessions` langsung dicabut (revoked) seketika**, memutus akses di aplikasi mobile.
- **SUSPENDED / REJECTED -> APPROVED**: Superadmin mengaktifkan kembali akun melalui `POST /api/v1/superadmin/users/{id}/reactivate`.
- **Revoke Sessions**: Superadmin dapat mencabut seluruh sesi aktif pengguna tanpa mengubah status akun melalui `POST /api/v1/superadmin/users/{id}/revoke-sessions`.

---

## 3. Telemetri Kesehatan Sistem & Metrik

Portal Superadmin memantau 6 komponen infrastruktur utama:

| Komponen | Target Pemantauan | Status Normal | Status Degradasi | Status Down |
| :--- | :--- | :--- | :--- | :--- |
| **API Gateway** | HTTP Listener & Routing | Liveness & Readiness 200 OK | Response time lambat | HTTP Server error |
| **PostgreSQL** | Connection Pool Ping | Ping selesai < 500ms | Ping > 2000ms | Connection refused / down |
| **GOWA Gateway** | WhatsApp Web Multidevice | API Ready & Device Paired | Device unlinked / QR pending | GOWA Service unreachable |
| **Outbox Worker** | Notifikasi WhatsApp Dispatcher | Background worker running | Retry queue menumpuk | Worker stopped |
| **Realtime WS** | Order Broadcast WebSocket | Hub open, streaming aktif | Backpressure high | WS Hub closed |
| **Mobile Sync** | Offline-First Sync Channel | Sinkronisasi batch normal | Konflik versi meningkat | Endpoint error |

### Rentang Waktu & Agregasi Telemetri:
- Pilihan rentang waktu: `15m` (15 menit), `1h` (1 jam), `24h` (24 jam, default), `7d` (7 hari).
- Metrik mencakup:
  - **Request Rate per Menit**
  - **Success Rate (%)**
  - **Latensi p50 & p95 (ms)**
  - **WhatsApp Messages (Inbound vs Outbound)**
  - **Antrean Pesanan Aktif (Pending, Preparing, Ready)**
  - **Status Sinkronisasi Mobile (Success, Failure, Conflict)**

---

## 4. Runbook Operasional Superadmin

### A. Bootstrap Akun Superadmin Pertama
Gunakan CLI bootstrap berizin di server backend:
```bash
cd pesenhub_be
go run ./cmd/bootstrap-superadmin --email admin.utama@pesenhub.id --name "Superadmin Utama"
```

### B. Mengakses Portal Web
1. Buka peramban ke: `http://<host>:8080/superadmin/`
2. Masukkan sesi token Superadmin yang valid pada halaman autentikasi.
3. Klik **"Masuk ke Portal"**.
4. Setelah terverifikasi, header akan menampilkan badge status sistem dan email Superadmin.

### C. Menyetujui Pendaftaran Owner Baru
1. Masuk ke tab **"Pengguna & Approval"**.
2. Klik filter pill **"Menunggu Approval"**.
3. Cari akun yang dituju, lalu klik tombol **"Setujui"**.
4. Masukkan alasan / catatan verifikasi (opsional, misal: "Verifikasi dokumen UMKM valid").
5. Klik **"Ya, Setujui Akun"**.
6. Akun berpindah ke status `APPROVED` dan dicatat ke log audit.

### D. Menangguhkan Akun & Membatalkan Sesi Aktif Seketika
1. Pada tab **"Pengguna & Approval"**, cari akun Owner yang melanggar kebijakan.
2. Klik tombol **"Tangguhkan"**.
3. Dialog peringatan native `<dialog>` akan muncul.
4. Masukkan alasan penangguhan kebijakan.
5. Klik **"Tangguhkan Akun"**.
6. Backend secara transaksional mengubah status menjadi `SUSPENDED` dan mengubah `revoked_at = now()` pada seluruh baris aktif di `app_sessions`.
7. Aplikasi mobile yang sedang berjalan akan menerima status unauthenticated / forbidden pada request berikutnya dan diarahkan ke layar login.

---

## 5. Matriks Endpoint API Superadmin

Seluruh endpoint di bawah berada di bawah prefix `/api/v1/superadmin/` dan mewajibkan otorisasi `SUPERADMIN`:

| Method | Path | Deskripsi | Status Respon |
| :--- | :--- | :--- | :--- |
| `GET` | `/health/snapshot` | Snapshot kondisi seluruh 6 komponen sistem | `200 OK` |
| `GET` | `/telemetry/traffic` | Metrik latensi, volume traffic, dan antrean | `200 OK` |
| `GET` | `/users` | Daftar pengguna dengan filter status & search | `200 OK` |
| `GET` | `/users/invitations` | Daftar undangan calon owner yang aktif | `200 OK` |
| `POST` | `/users/invite` | Buat undangan calon owner Google | `201 Created` |
| `DELETE` | `/users/invitations/{id}` | Batalkan/cabut undangan | `200 OK` |
| `POST` | `/users/{id}/approve` | Setujui pendaftaran akun owner | `200 OK` |
| `POST` | `/users/{id}/reject` | Tolak pendaftaran akun | `200 OK` |
| `POST` | `/users/{id}/suspend` | Tangguhkan akun & cabut seluruh sesi aktif | `200 OK` |
| `POST` | `/users/{id}/reactivate` | Aktifkan kembali akun yang ditangguhkan/ditolak | `200 OK` |
| `POST` | `/users/{id}/revoke-sessions` | Cabut seluruh sesi tanpa mengubah status | `200 OK` |
| `GET` | `/audits` | Riwayat audit aktivitas perubahan status | `200 OK` |
