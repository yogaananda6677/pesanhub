# Midtrans Payment Expiry and Reconciliation

## Boundary

Webhook Midtrans tetap jalur utama perubahan status pembayaran. Rekonsiliasi merupakan jalur pemulihan untuk charge `UNKNOWN`, webhook yang terlambat/hilang, dan status provider yang masih `pending` setelah QRIS melewati waktu kedaluwarsa. Rekonsiliasi tidak membuat payment/order baru, tidak mengubah status order, dan tidak menjalankan refund.

Backend memanggil `GET /v2/{order_id}/status` dengan Basic Authentication menggunakan server key sandbox. Hanya provider order ID yang stabil dikirim. Respons harus cocok dengan provider order ID, transaction ID yang sudah tersimpan, nominal backend, channel `qris`, mata uang `IDR`, dan daftar status yang diizinkan sebelum state payment boleh berubah.

## Expiry policy

`expires_at` hanya menentukan kapan payment perlu diperiksa. Payment menjadi `EXPIRED` hanya ketika Get Status API atau webhook terautentikasi memberikan `transaction_status=expire`. Bila provider tetap mengembalikan `pending` setelah `expires_at`, kondisi dicatat sebagai discrepancy dan masuk bounded retry; status payment tidak diubah berdasarkan jam lokal saja.

## State dan retry

State internal rekonsiliasi:

- `DUE`: siap diperiksa pada `reconciliation_next_at`.
- `IN_FLIGHT`: sudah diklaim atomik oleh satu worker. Claim lama dapat dipulihkan setelah dua menit.
- `RETRY`: kegagalan aman atau discrepancy dijadwalkan ulang dengan backoff 30 detik, 1, 2, 4, hingga maksimum 15 menit.
- `RESOLVED`: payment terminal atau status provider berhasil dikonfirmasi.
- `ALERT`: lima kegagalan berulang telah tercapai; pemrosesan otomatis berhenti.

Worker memakai row locking `SKIP LOCKED`, provider event ID deterministik, audit, dan deduplication key outbox. Karena itu worker paralel, restart, retry manual, dan event webhook yang datang bersamaan tidak menggandakan payment, event status, atau alert.

## Operasi manual dan observability

`POST /api/v1/payments/{id}/reconcile` hanya menerima principal staf. `200` menandakan respons provider tervalidasi. `202` dengan outcome `retry` atau `alert` menandakan payment tidak dianggap lunas dan tindak lanjut sudah dicatat. Payment terminal, non-QRIS, atau claim aktif ditolak dengan `409 PAYMENT_NOT_RECONCILABLE`.

Counter in-process mencakup claim, success, applied, duplicate, retry, alert, timeout, authentication failure, validation failure, dan persistence failure. Structured log hanya memuat outcome, payment ID, status provider, attempt, dan error code terkontrol. Server key, signature, raw response, serta data pelanggan tidak dicatat.

Saat alert muncul, operator harus memeriksa dashboard sandbox Midtrans dan request ID pada audit, lalu memicu rekonsiliasi manual setelah gangguan provider atau konfigurasi diselesaikan. Jangan menandai payment `PAID` secara manual dan jangan menyelesaikan order hanya dari status pembayaran.

Referensi resmi:

- [Midtrans Get Transaction Status](https://docs.midtrans.com/reference/get-transaction-status)
- [Midtrans HTTP notification/webhook](https://docs.midtrans.com/docs/https-notification-webhooks)
