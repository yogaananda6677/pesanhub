import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/order/controllers/order_detail_controller.dart';
import 'package:pesenhub_app/order/models/order_action.dart';
import 'package:pesenhub_app/order/order_detail_view.dart';
import 'package:pesenhub_app/order/widgets/order_payment_card.dart';
import 'package:pesenhub_app/order/widgets/order_status_timeline.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';

void main() {
  group(
    'Issue #29: Order Detail, Status Timeline, and Contextual Quick Action Tests',
    () {
      QueueOrder buildTestOrder({
        String id = 'ord-001',
        String orderNumber = 'ORD-PREP-1',
        String orderStatus = 'PREPARING',
        String paymentStatus = 'UNPAID',
        int version = 2,
        bool isTakeaway = true,
        String? takeawayNotes = 'Bungkus terpisah, kuah dipisah',
      }) {
        return QueueOrder(
          id: id,
          orderNumber: orderNumber,
          customerName: 'Mas Bambang',
          customerPhone: '081234567890',
          source: 'CASHIER_MANUAL',
          orderStatus: orderStatus,
          paymentStatus: paymentStatus,
          isTakeaway: isTakeaway,
          takeawayNotes: takeawayNotes,
          items: const [
            QueueOrderItem(
              name: 'Nasi Goreng Spesial',
              quantity: 2,
              unitPrice: 28000,
              notes: 'Pedas Level 2, Telur Ceplok',
              isDrink: false,
            ),
            QueueOrderItem(
              name: 'Es Teh Manis',
              quantity: 2,
              unitPrice: 5000,
              notes: 'Gula Normal',
              isDrink: true,
            ),
          ],
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          version: version,
        );
      }

      test(
        'Criteria #1: Given PREPARING, primary action is Tandai Siap with target READY_FOR_PICKUP',
        () {
          final order = buildTestOrder(orderStatus: 'PREPARING');
          final controller = OrderDetailController(
            initialOrder: order,
            role: 'STAFF',
          );

          final action = controller.primaryAction;
          expect(action, isNotNull);
          expect(action!.label, equals('Tandai Siap'));
          expect(action.targetStatus, equals('READY_FOR_PICKUP'));

          // Check other operational status mappings
          final pendingOrder = buildTestOrder(orderStatus: 'PENDING');
          final pendingController = OrderDetailController(
            initialOrder: pendingOrder,
            role: 'STAFF',
          );
          expect(
            pendingController.primaryAction!.label,
            equals('Terima Pesanan'),
          );
          expect(
            pendingController.primaryAction!.targetStatus,
            equals('ACCEPTED'),
          );

          final acceptedOrder = buildTestOrder(orderStatus: 'ACCEPTED');
          final acceptedController = OrderDetailController(
            initialOrder: acceptedOrder,
            role: 'STAFF',
          );
          expect(
            acceptedController.primaryAction!.label,
            equals('Mulai Masak'),
          );
          expect(
            acceptedController.primaryAction!.targetStatus,
            equals('PREPARING'),
          );

          final readyOrder = buildTestOrder(orderStatus: 'READY_FOR_PICKUP');
          final readyController = OrderDetailController(
            initialOrder: readyOrder,
            role: 'STAFF',
          );
          expect(
            readyController.primaryAction!.label,
            equals('Selesaikan Order'),
          );
          expect(
            readyController.primaryAction!.targetStatus,
            equals('COMPLETED'),
          );
        },
      );

      testWidgets(
        'Criteria #1: OrderDetailView renders Tandai Siap button when PREPARING and executes transition',
        (tester) async {
          final order = buildTestOrder(orderStatus: 'PREPARING');
          final controller = OrderDetailController(
            initialOrder: order,
            role: 'STAFF',
          );

          bool transitioned = false;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: OrderDetailView(
                  controller: controller,
                  transitionFn: (orderId, targetStatus, expectedVersion) async {
                    transitioned = true;
                    expect(targetStatus, equals('READY_FOR_PICKUP'));
                    expect(expectedVersion, equals(order.version));
                    return buildTestOrder(
                      orderStatus: 'READY_FOR_PICKUP',
                      version: order.version + 1,
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Tandai Siap'), findsOneWidget);
          await tester.tap(find.text('Tandai Siap'));
          await tester.pumpAndSettle();

          expect(transitioned, isTrue);
          expect(controller.order.orderStatus, equals('READY_FOR_PICKUP'));
          expect(controller.order.version, equals(3));
          expect(find.text('Selesaikan Order'), findsOneWidget);
        },
      );

      test(
        'Criteria #2: Stale version displays conflict warning and reloads fresh order without overwrite',
        () async {
          final order = buildTestOrder(orderStatus: 'PREPARING', version: 2);
          final controller = OrderDetailController(
            initialOrder: order,
            role: 'STAFF',
          );

          final serverOrderV3 = buildTestOrder(
            orderStatus: 'READY_FOR_PICKUP',
            version: 3,
          );

          final success = await controller.executeAction(
            controller.primaryAction!,
            transitionFn: (orderId, targetStatus, expectedVersion) async {
              throw Exception(
                'VERSION_CONFLICT: order version is stale (expected 2, got 3)',
              );
            },
            reloadFn: (orderId) async {
              return serverOrderV3;
            },
          );

          expect(success, isFalse);
          expect(controller.conflictMessage, contains('Konflik Versi'));
          // Server order state loaded without being overwritten
          expect(controller.order.orderStatus, equals('READY_FOR_PICKUP'));
          expect(controller.order.version, equals(3));
        },
      );

      testWidgets(
        'Criteria #3: Order status and payment status are strictly separated',
        (tester) async {
          final order = buildTestOrder(
            orderStatus: 'PREPARING',
            paymentStatus: 'UNPAID',
          );
          final controller = OrderDetailController(
            initialOrder: order,
            role: 'STAFF',
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(body: OrderDetailView(controller: controller)),
            ),
          );
          await tester.pumpAndSettle();

          // Separate Order Status Timeline is rendered
          expect(find.byType(OrderStatusTimeline), findsOneWidget);
          expect(find.text('Siklus Tahapan Pesanan'), findsOneWidget);
          expect(find.text('Memasak'), findsOneWidget);

          // Separate Payment Card is rendered
          expect(find.byType(OrderPaymentCard), findsOneWidget);
          expect(find.text('Status Pembayaran'), findsOneWidget);
          expect(find.text('Belum Bayar'), findsOneWidget);
        },
      );

      test(
        'Criteria #4: Unauthorized roles cannot execute forbidden transitions (Role Guard)',
        () async {
          final order = buildTestOrder(orderStatus: 'PREPARING');

          // 1. CUSTOMER: Read-only
          final customerController = OrderDetailController(
            initialOrder: order,
            role: 'CUSTOMER',
          );
          expect(customerController.primaryAction, isNull);
          expect(customerController.secondaryAction, isNull);

          final customerAttempt = await customerController.executeAction(
            const OrderAction(
              targetStatus: 'READY_FOR_PICKUP',
              label: 'Tandai Siap',
              icon: Icons.check,
            ),
          );
          expect(customerAttempt, isFalse);
          expect(
            customerController.errorMessage,
            contains('tidak memiliki izin'),
          );

          // 2. KDS: Kitchen Display (cannot accept, cancel, or complete cashier orders)
          final pendingOrder = buildTestOrder(orderStatus: 'PENDING');
          final kdsController = OrderDetailController(
            initialOrder: pendingOrder,
            role: 'KDS',
          );
          expect(kdsController.primaryAction, isNull); // KDS cannot accept

          // But when PREPARING, KDS can mark ready
          final prepOrder = buildTestOrder(orderStatus: 'PREPARING');
          final kdsPrepController = OrderDetailController(
            initialOrder: prepOrder,
            role: 'KDS',
          );
          expect(kdsPrepController.primaryAction, isNotNull);
          expect(
            kdsPrepController.primaryAction!.targetStatus,
            equals('READY_FOR_PICKUP'),
          );
        },
      );

      testWidgets(
        'Criteria #5: OrderDetailView renders cleanly on mobile and tablet with complete states',
        (tester) async {
          final order = buildTestOrder(
            orderStatus: 'PREPARING',
            isTakeaway: true,
            takeawayNotes: 'Pisah bumbu & kuah',
          );
          final controller = OrderDetailController(
            initialOrder: order,
            role: 'STAFF',
          );

          // 1. Mobile viewport (< 600dp)
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(body: OrderDetailView(controller: controller)),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('ORD-PREP-1'), findsOneWidget);
          expect(find.text('v2'), findsOneWidget);
          expect(find.text('Mas Bambang'), findsOneWidget);
          expect(find.text('Bungkus / Takeaway'), findsOneWidget);
          expect(
            find.text('Catatan Kemasan: Pisah bumbu & kuah'),
            findsOneWidget,
          );
          expect(find.text('Minuman Barista (1)'), findsOneWidget);
          expect(find.text('Menu Makanan / Dapur:'), findsOneWidget);

          // 2. Tablet viewport (>= 600dp)
          tester.view.physicalSize = const Size(1024, 768);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('ORD-PREP-1'), findsOneWidget);

          // 3. Error Banner state
          await controller.executeAction(
            controller.primaryAction!,
            transitionFn: (id, st, v) async {
              throw Exception('Koneksi internet terputus');
            },
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppBanner), findsOneWidget);
          expect(
            find.textContaining('Koneksi internet terputus'),
            findsOneWidget,
          );
        },
      );
    },
  );
}
