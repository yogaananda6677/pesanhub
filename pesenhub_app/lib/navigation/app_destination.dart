import 'package:flutter/material.dart';

/// AppDestination defines the navigation destinations available in the PesenHub App Shell.
enum AppDestination {
  dashboard,
  pos,
  queue,
  kds,
  menu,
  settings;

  String get label {
    switch (this) {
      case AppDestination.dashboard:
        return 'Ringkasan';
      case AppDestination.pos:
        return 'Kasir';
      case AppDestination.queue:
        return 'Antrean';
      case AppDestination.kds:
        return 'Dapur KDS';
      case AppDestination.menu:
        return 'Menu';
      case AppDestination.settings:
        return 'Pengaturan';
    }
  }

  String get title {
    switch (this) {
      case AppDestination.dashboard:
        return 'Ringkasan Operasional';
      case AppDestination.pos:
        return 'Kasir — Buat Pesanan';
      case AppDestination.queue:
        return 'Antrean Pesanan';
      case AppDestination.kds:
        return 'Dapur KDS — Tiket Memasak';
      case AppDestination.menu:
        return 'Kelola Ketersediaan Menu';
      case AppDestination.settings:
        return 'Pengaturan Outlet';
    }
  }

  IconData get icon {
    switch (this) {
      case AppDestination.dashboard:
        return Icons.dashboard_outlined;
      case AppDestination.pos:
        return Icons.point_of_sale_outlined;
      case AppDestination.queue:
        return Icons.receipt_long_outlined;
      case AppDestination.kds:
        return Icons.outdoor_grill_outlined;
      case AppDestination.menu:
        return Icons.restaurant_menu_outlined;
      case AppDestination.settings:
        return Icons.settings_outlined;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case AppDestination.dashboard:
        return Icons.dashboard_rounded;
      case AppDestination.pos:
        return Icons.point_of_sale_rounded;
      case AppDestination.queue:
        return Icons.receipt_long_rounded;
      case AppDestination.kds:
        return Icons.outdoor_grill_rounded;
      case AppDestination.menu:
        return Icons.restaurant_menu_rounded;
      case AppDestination.settings:
        return Icons.settings_rounded;
    }
  }

  static AppDestination fromIndex(int index) {
    if (index < 0 || index >= AppDestination.values.length) {
      return AppDestination.dashboard;
    }
    return AppDestination.values[index];
  }
}
