# pesenhub_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Menjalankan aplikasi lokal

Salin `config/runtime.example.json` menjadi `config/runtime.local.json`, lalu
isi URL backend dan Google Web Client ID. Untuk Android emulator gunakan
`http://10.0.2.2:8080`; untuk perangkat fisik gunakan IP LAN komputer, misalnya
`http://192.168.1.10:8080` (bukan `localhost`).

```bash
flutter devices
flutter run -d <device-id> --dart-define-from-file=config/runtime.local.json
```

File `runtime.local.json` adalah konfigurasi lokal dan tidak boleh memuat secret
backend, Gmail App Password, atau API key Hermes.
