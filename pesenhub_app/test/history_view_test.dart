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

    testWidgets(
      'displays explicit payment badge (Lunas/Belum Bayar) and localized order status for PENDING and READY_FOR_PICKUP orders',
      (tester) async {
        final pendingPaidOrder = QueueOrder(
          id: 'ord-103',
          orderNumber: 'ORD-20261030-103',
          customerName: 'Siti Rahma',
          customerPhone: '08111222333',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          paymentMethod: 'CASH',
          createdAt: DateTime(2026, 10, 30, 14, 0),
          items: const [
            QueueOrderItem(
              name: 'Martabak Telur Spesial',
              quantity: 1,
              unitPrice: 35000,
            ),
          ],
          subtotalAmount: 35000,
        );

        final readyOrder = QueueOrder(
          id: 'ord-104',
          orderNumber: 'ORD-20261030-104',
          customerName: 'Ahmad Fauzi',
          customerPhone: '08555666777',
          source: 'CASHIER_MANUAL',
          orderStatus: 'READY_FOR_PICKUP',
          paymentStatus: 'UNPAID',
          paymentMethod: 'CASH',
          createdAt: DateTime(2026, 10, 30, 14, 30),
          items: const [
            QueueOrderItem(
              name: 'Terang Bulan Coklat Keju',
              quantity: 1,
              unitPrice: 25000,
            ),
          ],
          subtotalAmount: 25000,
        );

        final testController = HistoryController(
          initialOrders: [pendingPaidOrder, readyOrder],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: HistoryView(controller: testController)),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify ORD-103 (PENDING + PAID):
        // Shows 'Lunas' payment badge and 'Menunggu' order status badge, NEVER raw 'PENDING'
        expect(find.text('Lunas'), findsOneWidget);
        expect(find.text('Menunggu'), findsOneWidget);
        expect(find.text('PENDING'), findsNothing);

        // 2. Verify ORD-104 (READY_FOR_PICKUP + UNPAID):
        // Shows 'Belum Bayar' payment badge and 'Siap Diambil' order status badge, NEVER raw 'READY_FOR_PICKUP'
        expect(find.text('Belum Bayar'), findsOneWidget);
        expect(find.text('Siap Diambil'), findsOneWidget);
        expect(find.text('READY_FOR_PICKUP'), findsNothing);
      },
    );

    testWidgets(
      'order receipt modal displays both payment status badge and localized order status',
      (tester) async {
        final pendingPaidOrder = QueueOrder(
          id: 'ord-105',
          orderNumber: 'ORD-20261030-105',
          customerName: 'Dewi Lestari',
          customerPhone: '0812344321',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          paymentMethod: 'CASH',
          createdAt: DateTime(2026, 10, 30, 15, 0),
          items: const [
            QueueOrderItem(
              name: 'Martabak Daging Sapi',
              quantity: 1,
              unitPrice: 45000,
            ),
          ],
          subtotalAmount: 45000,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('open-receipt-button'),
                  onPressed: () => OrderReceiptModal.show(
                    context,
                    order: pendingPaidOrder,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open-receipt-button')));
        await tester.pumpAndSettle();

        // Header badges should display 'LUNAS' and 'MENUNGGU'
        expect(find.text('LUNAS'), findsOneWidget);
        expect(find.text('MENUNGGU'), findsOneWidget);
        expect(find.text('PENDING'), findsNothing);

        // Detail payment row should display 'Tunai • Lunas'
        expect(find.text('Tunai • Lunas'), findsOneWidget);
      },
    );
  });
}
