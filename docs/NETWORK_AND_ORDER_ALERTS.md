# Network and Order Alerts

Issue #35 menambahkan indikator koneksi yang selalu memakai teks, ikon, dan semantic label—bukan warna saja. State yang didukung adalah `Online`, `Offline`, dan `Menyinkronkan`. `connectivity_plus` menunjukkan ketersediaan jalur jaringan; keberhasilan request Backend tetap menjadi sumber kebenaran akses internet.

## Perilaku foreground dan background

| Kondisi | Perilaku |
| --- | --- |
| Foreground | Heads-up in-app non-blocking, system alert sound, dan medium haptic feedback |
| Background + permission granted | Local notification high-priority dengan vibration/sound platform |
| Background + permission denied/error | Alert disimpan sementara dan tampil sebagai heads-up saat aplikasi kembali foreground |
| Duplicate event ID | Diabaikan |
| Event berbeda untuk order/kind yang sama dalam 5 detik | Di-throttle untuk mencegah alarm fatigue |

Permission hanya diminta setelah pengguna menekan tombol lonceng. Notification lock-screen memakai visibility `private`; judul/body hanya memuat nomor order dan status, tidak memuat nama atau nomor telepon pelanggan. Remote push dan reminder terjadwal tidak termasuk scope ini.

## Verifikasi

```bash
cd pesenhub_app
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

Manual device/emulator:

1. Buka aplikasi pada mobile dan tablet, lalu matikan/aktifkan Wi-Fi untuk memeriksa label Offline/Online.
2. Picu state sync dan pastikan label `Menyinkronkan` terlihat.
3. Izinkan notifikasi, kirim satu event order ketika aplikasi foreground dan background, lalu pastikan masing-masing hanya satu alert.
4. Tolak permission, kirim event ketika background, lalu buka aplikasi dan pastikan heads-up fallback muncul.
5. Ulangi event ID yang sama serta burst event dalam lima detik untuk memastikan tidak ada alert ganda.
6. Periksa silent/ringer mode: aplikasi menghormati pengaturan OS dan tidak melewati Do Not Disturb.

Audio, vibration, permission prompt, dan heads-up background harus diverifikasi pada perangkat/emulator Android/iOS target sebelum pilot karena runner CI tidak menyediakan perangkat dengan notification tray dan speaker.
