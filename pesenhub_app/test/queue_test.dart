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
  final fixedNow = DateTime(2026, 9, 4, 12, 30);

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

  Widget buildQueueTestApp(QueueController controller) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: QueueView(controller: controller)),
    );
  }

  group('Issue #26: Unified Order Queue Tests', () {
    testWidgets(
      'Criteria #1: Three MVP sources render distinct text and icon badges',
      (tester) async {
        final orders = [
          buildOrder(
            id: 'ord-1',
            orderNumber: '#ORD-001',
            customerName: 'Customer WA',
            source: 'WHATSAPP',
            orderStatus: 'PENDING',
            paymentStatus: 'PAID',
          ),
          buildOrder(
            id: 'ord-2',
            orderNumber: '#ORD-002',
            customerName: 'Customer Web',
            source: 'CUSTOMER_WEB',
            orderStatus: 'PENDING',
            paymentStatus: 'UNPAID',
          ),
          buildOrder(
            id: 'ord-3',
            orderNumber: '#ORD-003',
            customerName: 'Kasir Meja 1',
            source: 'CASHIER_MANUAL',
            orderStatus: 'PENDING',
            paymentStatus: 'PAID',
          ),
        ];

        final controller = QueueController(
          initialOrders: orders,
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        // Verify all 3 MVP source badges
        expect(find.text('WhatsApp'), findsAtLeastNWidgets(1));
        expect(find.text('Web Customer'), findsAtLeastNWidgets(1));
        expect(find.text('Kasir Manual'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Criteria #2: Real-time upsert prevents duplicate cards and handles versions',
      (tester) async {
        final initial = buildOrder(
          id: 'ord-dup',
          orderNumber: '#ORD-DUP',
          customerName: 'Budi Santoso',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PENDING',
          paymentStatus: 'UNPAID',
          version: 1,
        );

        final controller = QueueController(
          initialOrders: [initial],
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        expect(find.byType(OrderQueueCard), findsOneWidget);
        expect(find.text('Menunggu Konfirmasi'), findsAtLeastNWidgets(1));

        // Upsert duplicate order event (same ID, updated status, higher version)
        final updated = initial.copyWith(orderStatus: 'PREPARING', version: 2);
        controller.upsertOrder(updated);
        await tester.pumpAndSettle();

        // Still only 1 card, not duplicated
        expect(find.byType(OrderQueueCard), findsOneWidget);
        expect(find.text('Sedang Dimasak'), findsAtLeastNWidgets(1));

        // Older event (version 1) is ignored and does not revert or duplicate
        final older = initial.copyWith(version: 1);
        controller.upsertOrder(older);
        await tester.pumpAndSettle();

        expect(find.byType(OrderQueueCard), findsOneWidget);
        expect(find.text('Sedang Dimasak'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Criteria #3: Overdue alert, drinks highlight, and takeaway notes visible on card',
      (tester) async {
        final specialOrder = buildOrder(
          id: 'ord-special',
          orderNumber: '#ORD-999',
          customerName: 'Siti Rahma',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PREPARING',
          paymentStatus: 'PAID',
          minutesAgo: 20, // > 15 minutes -> Overdue
          isTakeaway: true,
          takeawayNotes: 'Pisah sambal & tanpa sendok',
          items: const [
            QueueOrderItem(
              name: 'Nasi Goreng Spesial',
              quantity: 2,
              unitPrice: 30000,
              notes: 'Pedas level 2',
            ),
            QueueOrderItem(
              name: 'Es Teh Manis Jumbo',
              quantity: 2,
              unitPrice: 6000,
              notes: 'Sedikit es batu',
              isDrink: true,
            ),
          ],
        );

        final controller = QueueController(
          initialOrders: [specialOrder],
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        // 1. Overdue alert banner
        expect(
          find.text('TERLAMBAT (> 15 MENIT BELUM SELESAI)'),
          findsOneWidget,
        );

        // 2. Takeaway notes
        expect(find.text('Pesanan Dibungkus (Takeaway)'), findsOneWidget);
        expect(
          find.text('Catatan Bungkus: Pisah sambal & tanpa sendok'),
          findsOneWidget,
        );

        // 3. Drinks section
        expect(find.text('Minuman / Barista'), findsOneWidget);
        expect(
          find.text('2x Es Teh Manis Jumbo (Sedikit es batu)'),
          findsOneWidget,
        );

        // 4. Food section
        expect(find.text('2x Nasi Goreng Spesial'), findsOneWidget);
        expect(find.text('Catatan: Pedas level 2'), findsOneWidget);

        // 5. Total
        expect(find.text('Rp 72000'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #4: Stable sorting prioritizes overdue, PENDING FIFO, and recovery preserves order',
      (tester) async {
        final normalPending = buildOrder(
          id: 'ord-norm-pending',
          orderNumber: '#ORD-001',
          customerName: 'Normal Pending',
          source: 'WHATSAPP',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          minutesAgo: 5,
        );

        final olderPending = buildOrder(
          id: 'ord-old-pending',
          orderNumber: '#ORD-002',
          customerName: 'Older Pending',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
          minutesAgo: 10,
        );

        final overduePreparing = buildOrder(
          id: 'ord-overdue-prep',
          orderNumber: '#ORD-003',
          customerName: 'Overdue Preparing',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PREPARING',
          paymentStatus: 'PAID',
          minutesAgo: 18, // Overdue!
        );

        final readyOrder = buildOrder(
          id: 'ord-ready',
          orderNumber: '#ORD-004',
          customerName: 'Ready Order',
          source: 'CASHIER_MANUAL',
          orderStatus: 'READY_FOR_PICKUP',
          paymentStatus: 'PAID',
          minutesAgo: 8,
        );

        // Ingest in arbitrary order
        final controller = QueueController(
          initialOrders: [
            readyOrder,
            normalPending,
            overduePreparing,
            olderPending,
          ],
          timeOverride: fixedNow,
        );

        final sorted = controller.filteredOrders;
        // Overdue first
        expect(sorted[0].id, equals('ord-overdue-prep'));
        // Then oldest pending
        expect(sorted[1].id, equals('ord-old-pending'));
        // Then newer pending
        expect(sorted[2].id, equals('ord-norm-pending'));
        // Then ready order
        expect(sorted[3].id, equals('ord-ready'));

        // Simulate recovery snapshot reconnect
        controller.setSnapshot([
          normalPending,
          overduePreparing,
          readyOrder,
          olderPending,
        ], isStale: false);

        final recoveredSorted = controller.filteredOrders;
        expect(recoveredSorted[0].id, equals('ord-overdue-prep'));
        expect(recoveredSorted[1].id, equals('ord-old-pending'));
        expect(recoveredSorted[2].id, equals('ord-norm-pending'));
        expect(recoveredSorted[3].id, equals('ord-ready'));
      },
    );

    testWidgets('Criteria #5: Filter chips update visible order cards', (
      tester,
    ) async {
      final orders = [
        buildOrder(
          id: 'ord-w1',
          orderNumber: '#ORD-W1',
          customerName: 'WA Pending',
          source: 'WHATSAPP',
          orderStatus: 'PENDING',
          paymentStatus: 'PAID',
        ),
        buildOrder(
          id: 'ord-c1',
          orderNumber: '#ORD-C1',
          customerName: 'Cashier Prep',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PREPARING',
          paymentStatus: 'PAID',
        ),
      ];

      final controller = QueueController(
        initialOrders: orders,
        timeOverride: fixedNow,
      );
      await tester.pumpWidget(buildQueueTestApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('#ORD-W1'), findsOneWidget);
      expect(find.text('#ORD-C1'), findsOneWidget);

      // Tap filter status 'Menunggu'
      await tester.tap(find.text('Menunggu (1)'));
      await tester.pumpAndSettle();

      expect(find.text('#ORD-W1'), findsOneWidget);
      expect(find.text('#ORD-C1'), findsNothing);

      // Tap filter status 'Semua'
      await tester.tap(find.text('Semua (2)'));
      await tester.pumpAndSettle();

      // Tap filter source 'WhatsApp'
      await tester.tap(find.text('WhatsApp').first);
      await tester.pumpAndSettle();

      expect(find.text('#ORD-W1'), findsOneWidget);
      expect(find.text('#ORD-C1'), findsNothing);
    });

    testWidgets(
      'Criteria #5: Complete presentation states (Loading, Empty, Error, Stale)',
      (tester) async {
        final controller = QueueController(timeOverride: fixedNow);

        // 1. Loading state
        await tester.pumpWidget(buildQueueTestApp(controller));
        expect(find.byType(AppLoadingState), findsOneWidget);

        // 2. Empty state
        controller.setSnapshot([]);
        await tester.pumpAndSettle();
        expect(find.byType(AppEmptyState), findsOneWidget);
        expect(find.text('Tidak Ada Pesanan'), findsOneWidget);

        // 3. Error state with retry
        controller.setError('Koneksi antrean terputus.');
        await tester.pumpAndSettle();
        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.text('Koneksi antrean terputus.'), findsOneWidget);

        // 4. Stale state
        controller.setSnapshot([
          buildOrder(
            id: 'ord-stale',
            orderNumber: '#ORD-STALE',
            customerName: 'Stale Order',
            source: 'CUSTOMER_WEB',
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
      'Criteria #5: Responsive layout on mobile and tablet without overflow',
      (tester) async {
        final orders = List.generate(4, (i) {
          return buildOrder(
            id: 'ord-resp-$i',
            orderNumber: '#ORD-R$i',
            customerName: 'Pelanggan $i',
            source: i % 2 == 0 ? 'WHATSAPP' : 'CUSTOMER_WEB',
            orderStatus: i % 2 == 0 ? 'PENDING' : 'PREPARING',
            paymentStatus: 'PAID',
            isTakeaway: true,
            takeawayNotes: 'Bungkus rapi $i',
            items: [
              QueueOrderItem(
                name: 'Nasi Goreng $i',
                quantity: 1,
                unitPrice: 25000,
                notes: 'Catatan $i',
              ),
              QueueOrderItem(
                name: 'Es Teh $i',
                quantity: 1,
                unitPrice: 5000,
                isDrink: true,
              ),
            ],
          );
        });

        final controller = QueueController(
          initialOrders: orders,
          timeOverride: fixedNow,
        );

        // Test mobile viewport
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Test tablet viewport
        tester.view.physicalSize = const Size(1024, 768);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
