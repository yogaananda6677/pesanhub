import 'package:flutter/material.dart';

/// AppDestination defines the 5 primary operational navigation destinations
/// available in the PesenHub App Shell (Issue #178).
enum AppDestination {
  dashboard,
  pos,
  queue,
  history,
  finance;

  String get label {
    switch (this) {
      case AppDestination.dashboard:
        return 'Beranda';
      case AppDestination.pos:
        return 'Kasir';
      case AppDestination.queue:
        return 'Antrean';
      case AppDestination.history:
        return 'Riwayat';
      case AppDestination.finance:
        return 'Keuangan';
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
      case AppDestination.history:
        return 'Riwayat Transaksi';
      case AppDestination.finance:
        return 'Laporan & Keuangan';
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
      case AppDestination.history:
        return Icons.history_outlined;
      case AppDestination.finance:
        return Icons.account_balance_wallet_outlined;
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
      case AppDestination.history:
        return Icons.history_rounded;
      case AppDestination.finance:
        return Icons.account_balance_wallet_rounded;
    }
  }

  static AppDestination fromIndex(int index) {
    if (index < 0 || index >= AppDestination.values.length) {
      return AppDestination.dashboard;
    }
    return AppDestination.values[index];
  }
}
