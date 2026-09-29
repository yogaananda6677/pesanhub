import 'package:flutter/material.dart';

/// AppDestination defines the navigation destinations available in the PesenHub App Shell.
enum AppDestination {
  dashboard,
  pos,
  queue,
  settings;

  String get label {
    switch (this) {
      case AppDestination.dashboard:
        return 'Ringkasan';
      case AppDestination.pos:
        return 'Kasir';
      case AppDestination.queue:
        return 'Transaksi';
      case AppDestination.settings:
        return 'Akun';
    }
  }

  String get title {
    switch (this) {
      case AppDestination.dashboard:
        return 'Ringkasan Operasional';
      case AppDestination.pos:
        return 'Kasir — Buat Pesanan';
      case AppDestination.queue:
        return 'Antrean Dapur';
      case AppDestination.settings:
        return 'Pengaturan Outlet';
    }
  }

  IconData get icon {
    switch (this) {
      case AppDestination.dashboard:
        return Icons.home_outlined;
      case AppDestination.pos:
        return Icons.point_of_sale_outlined;
      case AppDestination.queue:
        return Icons.receipt_long_outlined;
      case AppDestination.settings:
        return Icons.person_outline_rounded;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case AppDestination.dashboard:
        return Icons.home_rounded;
      case AppDestination.pos:
        return Icons.point_of_sale_rounded;
      case AppDestination.queue:
        return Icons.receipt_long_rounded;
      case AppDestination.settings:
        return Icons.person_rounded;
    }
  }

  static AppDestination fromIndex(int index) {
    if (index < 0 || index >= AppDestination.values.length) {
      return AppDestination.dashboard;
    }
    return AppDestination.values[index];
  }
}
