import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/cart/widgets/order_success_dialog.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:pesenhub_app/settings/services/printer_service.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  group('PrinterService Unit Tests', () {
    final printer = PrinterService.instance;

    setUp(() {
      printer.updateConfig(
        autoPrint: false, // disable auto print during unit tests
        kitchenCopy: false,
        autoCutter: true,
        paperSize: '58mm',
        isConnected: true,
      );
    });

    test('lineWidth corresponds to paper size', () {
      printer.updateConfig(paperSize: '58mm');
      expect(printer.lineWidth, equals(32));

      printer.updateConfig(paperSize: '80mm');
      expect(printer.lineWidth, equals(48));
    });

    test('updateConfig modifies settings and notifies listeners', () {
      bool notified = false;
      printer.addListener(() => notified = true);

      printer.updateConfig(
        autoPrint: true,
        kitchenCopy: true,
        autoCutter: false,
        paperSize: '80mm',
        deviceName: 'Custom Thermal POS',
      );

      expect(notified, isTrue);
      expect(printer.autoPrint, isTrue);
      expect(printer.kitchenCopy, isTrue);
      expect(printer.autoCutter, isFalse);
      expect(printer.paperSize, equals('80mm'));
      expect(printer.deviceName, equals('Custom Thermal POS'));
    });

    test(
      'formatReceipt produces clean thermal receipt with items and totals',
      () {
        printer.updateConfig(paperSize: '58mm', autoCutter: true);

        final order = QueueOrder(
          id: 'ord-123',
          orderNumber: 'ORD-20261017-001',
          customerName: 'Yoga Ananda',
          customerPhone: '081234567890',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          isTakeaway: true,
          takeawayNotes: 'Jangan terlalu manis',
          createdAt: DateTime(2026, 10, 17, 21, 30),
          items: const [
            QueueOrderItem(
              name: 'Terang Bulan Coklat Keju',
              quantity: 2,
              unitPrice: 25000,
            ),
            QueueOrderItem(
              name: 'Es Teh Manis',
              quantity: 1,
              unitPrice: 5000,
              isDrink: true,
              notes: 'Sedikit es',
            ),
          ],
          subtotalAmount: 55000,
          discountAmount: 5000,
          discountName: 'Diskon Mahasiswa',
        );

        final receipt = printer.formatReceipt(order);

        // Verify essential sections
        expect(receipt.contains('PESENHUB POS'), isTrue);
        expect(receipt.contains('ORD-20261017-001'), isTrue);
        expect(receipt.contains('Yoga Ananda'), isTrue);
        expect(receipt.contains('Takeaway'), isTrue);
        expect(receipt.contains('Jangan terlalu manis'), isTrue);
        expect(receipt.contains('Terang Bulan Coklat Keju'), isTrue);
        expect(receipt.contains('2 x 25.000'), isTrue);
        expect(receipt.contains('Es Teh Manis'), isTrue);
        expect(receipt.contains('Catatan: Sedikit es'), isTrue);
        expect(receipt.contains('Subtotal'), isTrue);
        expect(receipt.contains('Diskon (Diskon Mahasiswa)'), isTrue);
        expect(receipt.contains('TOTAL AKHIR'), isTrue);
        expect(receipt.contains('Rp 50.000'), isTrue);
        expect(receipt.contains('[AUTO CUT]'), isTrue);
      },
    );

    test(
      'printReceipt and printTestReceipt return status based on connection',
      () async {
        final order = QueueOrder(
          id: 'ord-1',
          orderNumber: 'ORD-1',
          customerName: 'Budi',
          customerPhone: '081',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          createdAt: DateTime.now(),
        );

        printer.updateConfig(isConnected: true);
        expect(await printer.printReceipt(order), isTrue);
        expect(await printer.printTestReceipt(), isTrue);

        printer.updateConfig(isConnected: false);
        expect(await printer.printReceipt(order), isFalse);
        expect(await printer.printTestReceipt(), isFalse);
      },
    );
  });

  group('OrderSuccessDialog Widget Tests', () {
    setUp(() {
      PrinterService.instance.updateConfig(autoPrint: false, isConnected: true);
    });

    testWidgets('renders success dialog with print button and preview action', (
      tester,
    ) async {
      final order = QueueOrder(
        id: 'ord-test-1',
        orderNumber: 'ORD-TEST-001',
        customerName: 'Rydo Pratama',
        customerPhone: '0811223344',
        source: 'CASHIER_MANUAL',
        orderStatus: 'PENDING',
        paymentStatus: 'PAID',
        isTakeaway: false,
        createdAt: DateTime(2026, 10, 17, 21, 0),
        items: const [
          QueueOrderItem(
            name: 'Martabak Telur Sapi',
            quantity: 1,
            unitPrice: 35000,
          ),
        ],
        subtotalAmount: 35000,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    OrderSuccessDialog.show(context: context, order: order),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify UI elements
      expect(find.text('Pesanan Berhasil Dibuat!'), findsOneWidget);
      expect(find.text('ORD-TEST-001'), findsOneWidget);
      expect(find.text('Rydo Pratama'), findsOneWidget);
      expect(find.text('Makan di Tempat'), findsOneWidget);
      expect(find.text('Rp 35.000'), findsOneWidget);
      expect(find.byKey(const Key('print-receipt-button')), findsOneWidget);
      expect(find.byKey(const Key('preview-receipt-button')), findsOneWidget);

      // Tap Cetak Struk
      await tester.tap(find.byKey(const Key('print-receipt-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Feedback should appear
      expect(
        find.textContaining('Struk berhasil dikirim ke printer thermal'),
        findsOneWidget,
      );

      // Tap Pratinjau Struk
      await tester.tap(find.byKey(const Key('preview-receipt-button')));
      await tester.pumpAndSettle();

      expect(find.text('Pratinjau Struk Thermal'), findsOneWidget);
      expect(find.textContaining('Martabak Telur Sapi'), findsOneWidget);
      expect(find.text('Cetak Sekarang'), findsOneWidget);
    });
  });
}
