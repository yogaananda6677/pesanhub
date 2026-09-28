# Autentikasi Admin dan Kasir

## Alur akses

1. Admin login dengan Google. Akun Admin baru berstatus `PENDING_APPROVAL`
   sampai disetujui Superadmin.
2. Admin yang sudah aktif mengirim undangan melalui
   `POST /api/v1/admin/cashiers/invitations` dengan body
   `{"email":"kasir@gmail.com"}`.
3. Backend menyimpan undangan dengan role tetap `CASHIER` dan masa berlaku tujuh
   hari. Role dari Flutter, query string, dan isi email tidak pernah dipercaya.
4. Gmail SMTP mengirim pemberitahuan bila `INVITE_EMAIL_ENABLED=true`.
5. Kasir menekan login Google di Flutter memakai email undangan. Backend
   memverifikasi ID token dan status `email_verified` dari Google, lalu dalam
   satu transaksi membuat akun `CASHIER/APPROVED` dan menandai undangan
   `ACCEPTED`.

Kasir dapat mengoperasikan POS, antrean, order, dan pembayaran. Kasir tidak
dapat mengubah katalog atau mengundang pengguna. Admin dapat melakukan keduanya.

## Gmail gratis untuk development

Aktifkan 2-Step Verification pada akun Google pengirim, buat App Password, lalu
isi konfigurasi lokal backend berikut (jangan commit nilainya):

```dotenv
INVITE_EMAIL_ENABLED=true
GMAIL_SMTP_USERNAME=akun.pengirim@gmail.com
GMAIL_SMTP_APP_PASSWORD=app_password_16_karakter
INVITE_EMAIL_FROM_NAME=PesenHub
INVITE_LOGIN_URL=https://alamat-aplikasi-anda
```

SMTP Gmail cocok untuk development dan volume kecil. App Password hanya berada
di backend. `INVITE_LOGIN_URL` boleh HTTP di environment `development`, tetapi
wajib HTTPS di environment lain. Bila pengiriman email gagal, undangan tetap
tersimpan dan endpoint mengembalikan `503 INVITATION_EMAIL_FAILED`; Admin dapat
mengirim ulang setelah konfigurasi diperbaiki.

## Migrasi

Jalankan dari direktori `pesenhub_be`:

```bash
./run.sh migrate-up
./run.sh migrate-status
```

Migration `000002` mengubah data role lama `OWNER` menjadi `ADMIN` dan menambah
metadata penerimaan undangan Kasir.
