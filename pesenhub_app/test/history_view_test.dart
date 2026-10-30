import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/history/controllers/history_controller.dart';
import 'package:pesenhub_app/history/views/history_view.dart';
import 'package:pesenhub_app/history/widgets/order_receipt_modal.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:pesenhub_app/settings/services/printer_service.dart';

void main() {
  group('HistoryView Widget Tests', () {
    late List<QueueOrder> sampleOrders;
    late HistoryController controller;

    setUp(() {
      sampleOrders = [
        QueueOrder(
          id: 'ord-101',
          orderNumber: 'ORD-20261030-101',
          customerName: 'Yoga Ananda',
          customerPhone: '081234567890',
          source: 'CASHIER_MANUAL',
          orderStatus: 'COMPLETED',
          paymentStatus: 'PAID',
          paymentMethod: 'CASH',
          createdAt: DateTime(2026, 10, 30, 12, 0),
          items: const [
            QueueOrderItem(
              name: 'Martabak Manis Coklat',
              quantity: 1,
              unitPrice: 30000,
            ),
          ],
          subtotalAmount: 30000,
        ),
        QueueOrder(
          id: 'ord-102',
          orderNumber: 'ORD-20261030-102',
          customerName: 'Budi Santoso',
          customerPhone: '08999888777',
          source: 'WHATSAPP',
          orderStatus: 'CANCELLED',
          paymentStatus: 'UNPAID',
          cancellationReason: 'Pelanggan minta dibatalkan',
          cancelledBy: 'Staf Kasir',
          createdAt: DateTime(2026, 10, 30, 13, 0),
          items: const [
            QueueOrderItem(
              name: 'Terang Bulan Keju',
              quantity: 2,
              unitPrice: 20000,
            ),
          ],
          subtotalAmount: 40000,
        ),
      ];
      controller = HistoryController(initialOrders: sampleOrders);
    });

    Widget createWidgetUnderTest() {
      return MaterialApp(
        home: Scaffold(body: HistoryView(controller: controller)),
      );
    }

    testWidgets('renders search bar, filter chips, and list of orders', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Check search input and filter chips
      expect(find.byKey(const Key('history-search-input')), findsOneWidget);
      expect(find.byKey(const Key('history-filter-all')), findsOneWidget);
      expect(find.byKey(const Key('history-filter-completed')), findsOneWidget);
      expect(find.byKey(const Key('history-filter-cancelled')), findsOneWidget);

      // Check both order cards are rendered
      expect(
        find.byKey(const Key('history-order-card-ORD-20261030-101')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('history-order-card-ORD-20261030-102')),
        findsOneWidget,
      );
      expect(find.text('Yoga Ananda • 1 menu'), findsOneWidget);
      expect(find.text('Budi Santoso • 1 menu'), findsOneWidget);
    });

    testWidgets('filtering by status updates the visible list', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap Selesai
      await tester.tap(find.byKey(const Key('history-filter-completed')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('history-order-card-ORD-20261030-101')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('history-order-card-ORD-20261030-102')),
        findsNothing,
      );

      // Tap Batal
      await tester.tap(find.byKey(const Key('history-filter-cancelled')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('history-order-card-ORD-20261030-101')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('history-order-card-ORD-20261030-102')),
        findsOneWidget,
      );
      expect(find.text('Alasan: Pelanggan minta dibatalkan'), findsOneWidget);
    });

    testWidgets(
      'typing in search bar filters orders and shows empty state if not found',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Enter search text
        await tester.enterText(
          find.byKey(const Key('history-search-input')),
          'Yoga',
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('history-order-card-ORD-20261030-101')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('history-order-card-ORD-20261030-102')),
          findsNothing,
        );

        // Enter unmatched query
        await tester.enterText(
          find.byKey(const Key('history-search-input')),
          'Zzz',
        );
        await tester.pumpAndSettle();

        expect(find.text('Tidak Ada Transaksi Ditemukan'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping an order card opens receipt modal with reprint action',
      (tester) async {
        final printer = PrinterService.instance;
        printer.updateConfig(isConnected: true);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('open-modal-button'),
                  onPressed: () => OrderReceiptModal.show(
                    context,
                    order: sampleOrders[1], // cancelled order
                    printerService: printer,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open-modal-button')));
        await tester.pumpAndSettle();

        // Verify receipt details
        expect(find.text('ORD-20261030-102'), findsOneWidget);
        expect(find.text('DIBATALKAN'), findsOneWidget);
        expect(find.text('Pesanan Dibatalkan'), findsOneWidget);
        expect(find.text('Alasan: Pelanggan minta dibatalkan'), findsOneWidget);
        expect(find.text('Dibatalkan oleh: Staf Kasir'), findsOneWidget);
        expect(find.text('Terang Bulan Keju'), findsOneWidget);
        expect(find.byKey(const Key('reprint-receipt-button')), findsOneWidget);

        // Tap reprint
        await tester.tap(find.byKey(const Key('reprint-receipt-button')));
        await tester.pump(); // Start print animation
        expect(find.text('Mencetak Struk...'), findsOneWidget);
        await tester.pumpAndSettle(); // Finish print delay

        expect(
          find.text('Struk pesanan #ORD-20261030-102 berhasil dicetak ulang.'),
          findsOneWidget,
        );
      },
    );
  });
}
