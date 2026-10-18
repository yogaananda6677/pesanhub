import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/utils/currency_formatter.dart';
import '../../queue/models/queue_order.dart';

/// PrinterService manages thermal receipt printer configuration, formatting,
/// and print jobs for POS checkout and test printing.
class PrinterService extends ChangeNotifier {
  static final PrinterService _instance = PrinterService._internal();
  static PrinterService get instance => _instance;

  PrinterService._internal();

  bool _autoPrint = true;
  bool _kitchenCopy = false;
  bool _autoCutter = true;
  String _paperSize = '58mm';
  String _deviceName = 'Xprinter XP-58II';
  String _deviceMac = '66:32:B1:8A:2C:90';
  bool _isConnected = true;
  bool _isPrinting = false;

  bool get autoPrint => _autoPrint;
  bool get kitchenCopy => _kitchenCopy;
  bool get autoCutter => _autoCutter;
  String get paperSize => _paperSize;
  String get deviceName => _deviceName;
  String get deviceMac => _deviceMac;
  bool get isConnected => _isConnected;
  bool get isPrinting => _isPrinting;

  void updateConfig({
    bool? autoPrint,
    bool? kitchenCopy,
    bool? autoCutter,
    String? paperSize,
    String? deviceName,
    String? deviceMac,
    bool? isConnected,
  }) {
    if (autoPrint != null) _autoPrint = autoPrint;
    if (kitchenCopy != null) _kitchenCopy = kitchenCopy;
    if (autoCutter != null) _autoCutter = autoCutter;
    if (paperSize != null) _paperSize = paperSize;
    if (deviceName != null) _deviceName = deviceName;
    if (deviceMac != null) _deviceMac = deviceMac;
    if (isConnected != null) _isConnected = isConnected;
    notifyListeners();
  }

  /// Width in characters for monospaced printing.
  int get lineWidth => _paperSize == '80mm' ? 48 : 32;

  String _divider([String char = '-']) {
    return List.filled(lineWidth, char).join();
  }

  String _center(String text) {
    if (text.length >= lineWidth) return text;
    final leftPadding = (lineWidth - text.length) ~/ 2;
    return ' ' * leftPadding + text;
  }

  String _justify(String left, String right) {
    final available = lineWidth - left.length - right.length;
    if (available <= 0) {
      return '$left\n${' ' * (lineWidth - right.length)}$right';
    }
    return '$left${' ' * available}$right';
  }

  /// Generates clean monospaced thermal receipt text.
  String formatReceipt(QueueOrder order) {
    final buffer = StringBuffer();

    // Store Header
    buffer.writeln(_divider('='));
    buffer.writeln(_center('PESENHUB POS'));
    buffer.writeln(_center('Martabak & Terang Bulan'));
    buffer.writeln(_center('Yogyakarta'));
    buffer.writeln(_divider('='));

    // Order Meta
    buffer.writeln(_justify('No. Nota :', order.orderNumber));
    buffer.writeln(_justify('Waktu    :', order.formattedDateTime));
    buffer.writeln(_justify('Kasir    :', 'Kasir Utama'));
    buffer.writeln(
      _justify(
        'Pelanggan:',
        order.customerName.isEmpty ? 'Umum' : order.customerName,
      ),
    );
    buffer.writeln(
      _justify('Layanan  :', order.isTakeaway ? 'Takeaway' : 'Dine In'),
    );
    if (order.takeawayNotes != null && order.takeawayNotes!.trim().isNotEmpty) {
      buffer.writeln('Catatan  : ${order.takeawayNotes!.trim()}');
    }
    buffer.writeln(_divider('-'));

    // Items Header
    buffer.writeln(_justify('ITEM', 'TOTAL'));
    buffer.writeln(_divider('-'));

    // Items
    for (final item in order.items) {
      buffer.writeln(item.name);
      final qtyPrice =
          '${item.quantity} x ${CurrencyFormatter.formatThousands(item.unitPrice)}';
      final itemTotal = CurrencyFormatter.formatThousands(item.subtotal);
      buffer.writeln(_justify('  $qtyPrice', itemTotal));

      if (item.notes != null && item.notes!.trim().isNotEmpty) {
        buffer.writeln('  Catatan: ${item.notes!.trim()}');
      }
    }

    buffer.writeln(_divider('-'));

    // Totals
    buffer.writeln(
      _justify('Subtotal', CurrencyFormatter.formatRupiah(order.subtotal)),
    );
    if ((order.discountAmount ?? 0) > 0) {
      final discLabel =
          order.discountName != null && order.discountName!.isNotEmpty
          ? 'Diskon (${order.discountName})'
          : 'Diskon Promo';
      buffer.writeln(
        _justify(
          discLabel,
          '-${CurrencyFormatter.formatRupiah(order.discountAmount)}',
        ),
      );
    }
    buffer.writeln(_divider('='));
    buffer.writeln(
      _justify(
        'TOTAL AKHIR',
        CurrencyFormatter.formatRupiah(order.totalAmount),
      ),
    );
    buffer.writeln(
      _justify(
        'Status Bayar',
        order.paymentStatus == 'PAID' ? 'LUNAS (CASH)' : order.paymentStatus,
      ),
    );
    buffer.writeln(_divider('='));

    // Footer
    buffer.writeln(_center('Terima kasih atas kunjungan Anda!'));
    buffer.writeln(_center('Simpan struk sebagai bukti pembayaran'));
    if (_autoCutter) {
      buffer.writeln(_center('[AUTO CUT]'));
    }
    buffer.writeln();

    return buffer.toString();
  }

  /// Simulates ESC/POS print command execution with async delay.
  Future<bool> printReceipt(QueueOrder order) async {
    if (!_isConnected) return false;
    _isPrinting = true;
    notifyListeners();
    try {
      // Simulate hardware transmission latency
      await Future<void>.delayed(const Duration(milliseconds: 650));
      return true;
    } catch (_) {
      return false;
    } finally {
      _isPrinting = false;
      notifyListeners();
    }
  }

  /// Prints test receipt.
  Future<bool> printTestReceipt() async {
    if (!_isConnected) return false;
    _isPrinting = true;
    notifyListeners();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (_) {
      return false;
    } finally {
      _isPrinting = false;
      notifyListeners();
    }
  }
}
