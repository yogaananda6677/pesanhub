import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/queue/controllers/queue_controller.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:pesenhub_app/queue/queue_view.dart';
import 'package:pesenhub_app/queue/widgets/order_queue_card.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';

void main() {
  final fixedNow = DateTime(2026, 9, 8, 12, 30);

  QueueOrder buildOrder({
    required String id,
    required String orderNumber,
    required String customerName,
    required String source,
    required String orderStatus,
    required String paymentStatus,
    int minutesAgo = 5,
    bool isTakeaway = false,
    String? takeawayNotes,
    List<QueueOrderItem> items = const [],
    int version = 1,
  }) {
    return QueueOrder(
      id: id,
      orderNumber: orderNumber,
      customerName: customerName,
      customerPhone: '0812****0000',
      source: source,
      orderStatus: orderStatus,
      paymentStatus: paymentStatus,
      isTakeaway: isTakeaway,
      takeawayNotes: takeawayNotes,
      items: items,
      createdAt: fixedNow.subtract(Duration(minutes: minutesAgo)),
      version: version,
    );
  }

  Widget buildQueueTestApp(
    QueueController controller, {
    void Function(QueueOrder order, String newStatus)? onStatusChanged,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: QueueView(
          controller: controller,
          onStatusChanged: onStatusChanged,
        ),
      ),
    );
  }

  group('Issue #147: Streamlined Antrean Dapur Tests', () {
    testWidgets(
      'Criteria #1: 3 Tabs (Menunggu, Diproses, Siap) render and filter correctly',
      (tester) async {
        final orders = [
          buildOrder(
            id: 'ord-1',
            orderNumber: '#ORD-001',
            customerName: 'Budi Santoso',
            source: 'WHATSAPP',
            orderStatus: 'PENDING',
            paymentStatus: 'PAID',
          ),
          buildOrder(
            id: 'ord-2',
            orderNumber: '#ORD-002',
            customerName: 'Siti Rahma',
            source: 'CUSTOMER_WEB',
            orderStatus: 'PREPARING',
            paymentStatus: 'PAID',
          ),
          buildOrder(
            id: 'ord-3',
            orderNumber: '#ORD-003',
            customerName: 'Ahmad Dani',
            source: 'CASHIER_MANUAL',
            orderStatus: 'READY_FOR_PICKUP',
            paymentStatus: 'PAID',
          ),
        ];

        final controller = QueueController(
          initialOrders: orders,
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        // Header and tabs exist
        expect(find.text('Antrean Dapur'), findsOneWidget);
        expect(find.text('Menunggu'), findsOneWidget);
        expect(find.text('Diproses'), findsOneWidget);
        expect(find.text('Siap'), findsOneWidget);

        // Tab 0 (Menunggu) shows only ord-1
        expect(find.byKey(const ValueKey('order_card_ord-1')), findsOneWidget);
        expect(find.text('Antrean 1'), findsOneWidget);
        expect(find.byKey(const ValueKey('order_card_ord-2')), findsNothing);
        expect(find.byKey(const ValueKey('order_card_ord-3')), findsNothing);

        // Switch to Tab 1 (Diproses)
        await tester.tap(find.text('Diproses'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('order_card_ord-2')), findsOneWidget);
        expect(find.text('Antrean 2'), findsOneWidget);
        expect(find.byKey(const ValueKey('order_card_ord-1')), findsNothing);
        expect(find.byKey(const ValueKey('order_card_ord-3')), findsNothing);

        // Switch to Tab 2 (Siap)
        await tester.tap(find.text('Siap'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('order_card_ord-3')), findsOneWidget);
        expect(find.text('Antrean 3'), findsOneWidget);
        expect(find.byKey(const ValueKey('order_card_ord-1')), findsNothing);
        expect(find.byKey(const ValueKey('order_card_ord-2')), findsNothing);
      },
    );

    testWidgets(
      'Criteria #2: Order card renders teal header, queue number, date/time, dining option, and items',
      (tester) async {
        final order = buildOrder(
          id: 'ord-1',
          orderNumber: '#ORD-1',
          customerName: 'Siti Rahma',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          isTakeaway: false,
          items: const [
            QueueOrderItem(
              name: 'Seblak Prasmanan',
              quantity: 1,
              unitPrice: 25000,
              notes: 'Level 0\nKuah Nyemek',
            ),
          ],
        );

        final controller = QueueController(
          initialOrders: [order],
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        expect(find.byType(OrderQueueCard), findsOneWidget);
        // Header title "Antrean 1"
        expect(find.text('Antrean 1'), findsOneWidget);
        // Receipt icon
        expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
        // Dining option badge
        expect(find.text('Makan di tempat'), findsOneWidget);
        // Item name & note
        expect(find.text('1 x Seblak Prasmanan'), findsOneWidget);
        expect(find.text('Level 0\nKuah Nyemek'), findsOneWidget);
        // Action button
        expect(find.text('Mulai Proses'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #3: 1-Tap lifecycle action transitions order status smoothly',
      (tester) async {
        QueueOrder? updatedOrder;
        String? nextStatus;

        final order = buildOrder(
          id: 'ord-prep',
          orderNumber: '#ORD-77',
          customerName: 'Joko Widodo',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PREPARING',
          paymentStatus: 'PAID',
        );

        final controller = QueueController(
          initialOrders: [order],
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(
          buildQueueTestApp(
            controller,
            onStatusChanged: (o, s) {
              updatedOrder = o;
              nextStatus = s;
            },
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Diproses tab
        await tester.tap(find.text('Diproses'));
        await tester.pumpAndSettle();

        // Tap action button "Siap Diambil"
        await tester.tap(find.text('Siap Diambil'));
        await tester.pumpAndSettle();

        expect(updatedOrder?.id, equals('ord-prep'));
        expect(nextStatus, equals('READY_FOR_PICKUP'));
      },
    );

    testWidgets(
      'Criteria #4: Overdue orders are prioritized in FIFO ordering',
      (tester) async {
        final normalOrder = buildOrder(
          id: 'ord-normal',
          orderNumber: '#ORD-001',
          customerName: 'Normal',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          minutesAgo: 5,
        );
        final overdueOrder = buildOrder(
          id: 'ord-overdue',
          orderNumber: '#ORD-002',
          customerName: 'Overdue',
          source: 'WHATSAPP',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          minutesAgo: 20, // Overdue
        );

        final controller = QueueController(
          initialOrders: [normalOrder, overdueOrder],
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        final cards = tester
            .widgetList<OrderQueueCard>(find.byType(OrderQueueCard))
            .toList();
        expect(cards.length, equals(2));
        // Overdue must be first
        expect(cards[0].order.id, equals('ord-overdue'));
        expect(cards[1].order.id, equals('ord-normal'));
      },
    );

    testWidgets(
      'Criteria #5: Real-time upsert prevents duplicate cards and handles versions',
      (tester) async {
        final initial = buildOrder(
          id: 'ord-dup',
          orderNumber: '#ORD-DUP',
          customerName: 'Budi Santoso',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          version: 1,
        );

        final controller = QueueController(
          initialOrders: [initial],
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        expect(find.byType(OrderQueueCard), findsOneWidget);

        // Upsert order to PREPARING
        final updated = initial.copyWith(orderStatus: 'PREPARING', version: 2);
        controller.upsertOrder(updated);
        await tester.pumpAndSettle();

        // In Menunggu tab, order disappeared because status is PREPARING
        expect(find.byType(OrderQueueCard), findsNothing);

        // Switch to Diproses tab
        await tester.tap(find.text('Diproses'));
        await tester.pumpAndSettle();

        expect(find.byType(OrderQueueCard), findsOneWidget);
        expect(find.text('Siap Diambil'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #6: Presentation states (Loading, Empty, Error, Stale)',
      (tester) async {
        final controller = QueueController(timeOverride: fixedNow);

        // 1. Loading
        await tester.pumpWidget(buildQueueTestApp(controller));
        expect(find.byType(AppLoadingState), findsOneWidget);

        // 2. Empty
        controller.setSnapshot([]);
        await tester.pumpAndSettle();
        expect(find.byType(AppEmptyState), findsOneWidget);
        expect(find.text('Tidak Ada Pesanan'), findsOneWidget);

        // 3. Error
        controller.setError('Koneksi terputus');
        await tester.pumpAndSettle();
        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.text('Koneksi terputus'), findsOneWidget);

        // 4. Stale banner
        controller.setSnapshot([
          buildOrder(
            id: 'ord-s',
            orderNumber: '#ORD-S',
            customerName: 'Stale',
            source: 'WHATSAPP',
            orderStatus: 'PENDING',
            paymentStatus: 'PAID',
          ),
        ], isStale: true);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Data Usang: Hubungan real-time terputus. Menampilkan snapshot terakhir.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criteria #7: Responsive layout on mobile and tablet without overflow',
      (tester) async {
        final orders = List.generate(4, (i) {
          return buildOrder(
            id: 'ord-resp-$i',
            orderNumber: '#ORD-R$i',
            customerName: 'Pelanggan $i',
            source: 'WHATSAPP',
            orderStatus: 'PENDING',
            paymentStatus: 'PAID',
            isTakeaway: i.isEven,
            items: [
              QueueOrderItem(
                name: 'Item $i',
                quantity: i + 1,
                unitPrice: 20000,
                notes: 'Catatan $i',
              ),
            ],
          );
        });

        final controller = QueueController(
          initialOrders: orders,
          timeOverride: fixedNow,
        );

        // Mobile
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Tablet
        tester.view.physicalSize = const Size(1024, 768);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
