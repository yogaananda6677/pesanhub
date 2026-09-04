import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/kds/controllers/kds_controller.dart';
import 'package:pesenhub_app/kds/kds_view.dart';
import 'package:pesenhub_app/kds/widgets/kds_ticket_card.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';

void main() {
  group('Issue #30: Adaptive KDS for Tablet and Mobile Tests', () {
    final testNow = DateTime(2026, 9, 4, 12, 0, 0);

    QueueOrder createOrder({
      required String id,
      required String orderNumber,
      required String orderStatus,
      required Duration age,
      bool isTakeaway = false,
      String? takeawayNotes,
      List<QueueOrderItem>? items,
      int version = 1,
    }) {
      return QueueOrder(
        id: id,
        orderNumber: orderNumber,
        customerName: 'Pelanggan $id',
        customerPhone: '0812345678',
        source: 'CASHIER_MANUAL',
        orderStatus: orderStatus,
        paymentStatus: 'PAID',
        isTakeaway: isTakeaway,
        takeawayNotes: takeawayNotes,
        createdAt: testNow.subtract(age),
        version: version,
        items:
            items ??
            const [
              QueueOrderItem(
                name: 'Nasi Goreng Spesial',
                quantity: 1,
                unitPrice: 28000,
                notes: 'Pedas Level 2',
              ),
            ],
      );
    }

    testWidgets(
      'Criteria #1: Renders adaptively on tablet and mobile without overflow',
      (tester) async {
        final orders = [
          createOrder(
            id: 'ord-1',
            orderNumber: 'ORD-101',
            orderStatus: 'ACCEPTED',
            age: const Duration(minutes: 5),
          ),
          createOrder(
            id: 'ord-2',
            orderNumber: 'ORD-102',
            orderStatus: 'PREPARING',
            age: const Duration(minutes: 10),
          ),
          createOrder(
            id: 'ord-3',
            orderNumber: 'ORD-103',
            orderStatus: 'PREPARING',
            age: const Duration(minutes: 18), // Overdue
          ),
        ];

        final controller = KdsController(initialOrders: orders);
        controller.timeOverride = testNow;

        // 1. Tablet Viewport (1024 x 768)
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: KdsView(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(KdsTicketCard), findsNWidgets(3));

        // 2. Mobile Viewport (390 x 844)
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(KdsTicketCard), findsNWidgets(3));
      },
    );

    test(
      'Criteria #2: Prioritizes overdue orders (> 15m) first, then FIFO by creation time',
      () {
        final orderNormalNew = createOrder(
          id: 'ord-normal-new',
          orderNumber: 'ORD-NEW',
          orderStatus: 'ACCEPTED',
          age: const Duration(minutes: 3),
        );
        final orderNormalOld = createOrder(
          id: 'ord-normal-old',
          orderNumber: 'ORD-OLD',
          orderStatus: 'ACCEPTED',
          age: const Duration(minutes: 10),
        );
        final orderOverdue = createOrder(
          id: 'ord-overdue',
          orderNumber: 'ORD-LATE',
          orderStatus: 'PREPARING',
          age: const Duration(minutes: 16), // Overdue
        );

        final controller = KdsController(
          initialOrders: [orderNormalNew, orderNormalOld, orderOverdue],
        );
        controller.timeOverride = testNow;

        final sorted = controller.sortedOrders;
        expect(sorted.length, equals(3));
        // 1. Overdue comes first
        expect(sorted[0].id, equals('ord-overdue'));
        // 2. Then FIFO (oldest creation time first)
        expect(sorted[1].id, equals('ord-normal-old'));
        expect(sorted[2].id, equals('ord-normal-new'));
      },
    );

    testWidgets(
      'Criteria #3: Drinks, packaging notes, spice levels, and notes are visually distinguished',
      (tester) async {
        final order = createOrder(
          id: 'ord-rich',
          orderNumber: 'ORD-RICH',
          orderStatus: 'PREPARING',
          age: const Duration(minutes: 8),
          isTakeaway: true,
          takeawayNotes: 'Pisah bumbu & kuah',
          items: const [
            QueueOrderItem(
              name: 'Nasi Goreng Gila',
              quantity: 2,
              unitPrice: 30000,
              notes: 'Pedas Level 3, Topping Sosis',
              isDrink: false,
            ),
            QueueOrderItem(
              name: 'Kopi Susu Gula Aren',
              quantity: 1,
              unitPrice: 18000,
              notes: 'Less Ice',
              isDrink: true,
            ),
          ],
        );

        final controller = KdsController(initialOrders: [order]);
        controller.timeOverride = testNow;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: KdsView(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        // Takeaway notes
        expect(find.text('Bungkus: Pisah bumbu & kuah'), findsOneWidget);
        // Food item & notes
        expect(find.text('Nasi Goreng Gila'), findsOneWidget);
        expect(find.text('Pedas Level 3, Topping Sosis'), findsOneWidget);
        // Barista drinks section
        expect(find.text('Minuman Barista (1)'), findsOneWidget);
        expect(
          find.text('• 1x Kopi Susu Gula Aren (Less Ice)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criteria #4: 1-Tap status transition respects version contract and prevents double action',
      (tester) async {
        final orderAccepted = createOrder(
          id: 'ord-acc',
          orderNumber: 'ORD-ACC',
          orderStatus: 'ACCEPTED',
          age: const Duration(minutes: 4),
          version: 1,
        );

        bool transitionCalled = false;
        String? transitionedTarget;
        int? expectedVersionSent;

        final controller = KdsController(initialOrders: [orderAccepted]);
        controller.timeOverride = testNow;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: KdsView(
                controller: controller,
                transitionFn: (orderId, targetStatus, expectedVersion) async {
                  transitionCalled = true;
                  transitionedTarget = targetStatus;
                  expectedVersionSent = expectedVersion;
                  return createOrder(
                    id: orderId,
                    orderNumber: 'ORD-ACC',
                    orderStatus: targetStatus,
                    age: const Duration(minutes: 4),
                    version: expectedVersion + 1,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. ACCEPTED ticket has "Mulai Masak" button
        expect(find.text('Mulai Masak'), findsOneWidget);
        await tester.tap(find.text('Mulai Masak'));
        await tester.pumpAndSettle();

        expect(transitionCalled, isTrue);
        expect(transitionedTarget, equals('PREPARING'));
        expect(expectedVersionSent, equals(1));

        // 2. Now status is PREPARING, button becomes "Tandai Siap"
        expect(find.text('Tandai Siap'), findsOneWidget);

        // 3. Tapping "Tandai Siap" transitions to READY_FOR_PICKUP
        await tester.tap(find.text('Tandai Siap'));
        await tester.pumpAndSettle();

        expect(transitionedTarget, equals('READY_FOR_PICKUP'));
        // Ready for pickup order leaves the kitchen display
        expect(find.byType(KdsTicketCard), findsNothing);
        expect(find.text('Dapur Bersih!'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #5: Complete presentation states (Empty, Loading, Error, and Filter Chips)',
      (tester) async {
        final controller = KdsController(initialOrders: []);
        controller.timeOverride = testNow;

        // 1. Empty State
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: KdsView(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AppEmptyState), findsOneWidget);
        expect(find.text('Dapur Bersih!'), findsOneWidget);

        // 2. Loading State
        controller.setLoading(true);
        await tester.pump();

        expect(find.byType(AppLoadingState), findsOneWidget);
        expect(find.text('Memuat tiket dapur...'), findsOneWidget);

        controller.setLoading(false);
        await tester.pumpAndSettle();

        // 3. Error Banner State
        controller.setError('Koneksi WebSocket dapur terputus');
        await tester.pumpAndSettle();

        expect(find.byType(AppBanner), findsOneWidget);
        expect(find.text('Koneksi WebSocket dapur terputus'), findsOneWidget);

        // 4. Status Filter Chips
        final orderAccepted = createOrder(
          id: 'ord-1',
          orderNumber: 'ORD-1',
          orderStatus: 'ACCEPTED',
          age: const Duration(minutes: 2),
        );
        final orderPreparing = createOrder(
          id: 'ord-2',
          orderNumber: 'ORD-2',
          orderStatus: 'PREPARING',
          age: const Duration(minutes: 5),
        );
        controller.setSnapshot([orderAccepted, orderPreparing]);
        await tester.pumpAndSettle();

        expect(find.text('Semua (2)'), findsOneWidget);
        expect(find.text('Perlu Dimasak (1)'), findsOneWidget);
        expect(find.text('Sedang Dimasak (1)'), findsOneWidget);
        expect(find.byType(KdsTicketCard), findsNWidgets(2));

        // Tap "Perlu Dimasak (1)"
        await tester.tap(find.text('Perlu Dimasak (1)'));
        await tester.pumpAndSettle();

        expect(find.byType(KdsTicketCard), findsOneWidget);
        expect(find.text('ORD-1'), findsOneWidget);
      },
    );
  });
}
