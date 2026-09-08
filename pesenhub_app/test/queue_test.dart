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

  Widget buildQueueTestApp(QueueController controller) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: QueueView(controller: controller)),
    );
  }

  group('Issue #26: Unified Order Queue Tests', () {
  group('Issue #147: Redesign Antrean Dapur Tests', () {
    testWidgets(
      'Criteria #1: Three MVP sources render distinct text and icon badges',
      'Criteria #1: Top Teal Header renders title "Antrean Dapur" and 3 tabs',
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
          initialOrders: [
            buildOrder(
              id: 'ord-1',
              orderNumber: '#ORD-1',
              customerName: 'Customer A',
              source: 'WHATSAPP',
              orderStatus: 'ACCEPTED',
              paymentStatus: 'PAID',
            ),
          ],
          timeOverride: fixedNow,
        );

        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        // Verify all 3 MVP source badges
        expect(find.text('WhatsApp'), findsAtLeastNWidgets(1));
        expect(find.text('Web Customer'), findsAtLeastNWidgets(1));
        expect(find.text('Kasir Manual'), findsAtLeastNWidgets(1));
        // Title and refresh action
        expect(find.text('Antrean Dapur'), findsOneWidget);
        expect(find.byKey(const Key('queue-refresh-button')), findsOneWidget);

        // 3 Tabs
        expect(find.text('Menunggu'), findsOneWidget);
        expect(find.text('Diproses'), findsOneWidget);
        expect(find.text('Siap'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #2: Real-time upsert prevents duplicate cards and handles versions',
      'Criteria #2: Order card renders teal header, queue number, date/time, dining option, and items',
      (tester) async {
        final initial = buildOrder(
          id: 'ord-dup',
          orderNumber: '#ORD-DUP',
          customerName: 'Budi Santoso',
        final order = buildOrder(
          id: 'ord-1',
          orderNumber: '#ORD-1',
          customerName: 'Siti Rahma',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PENDING',
          paymentStatus: 'UNPAID',
          version: 1,
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
          initialOrders: [initial],
          initialOrders: [order],
          timeOverride: fixedNow,
        );

        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        expect(find.byType(OrderQueueCard), findsOneWidget);
        expect(find.text('Menunggu Konfirmasi'), findsAtLeastNWidgets(1));
        // Card header
        expect(find.text('Antrean 1'), findsOneWidget);
        expect(find.text(order.formattedDateTime), findsOneWidget);
        expect(find.text('Makan di tempat'), findsOneWidget);

        // Upsert duplicate order event (same ID, updated status, higher version)
        final updated = initial.copyWith(orderStatus: 'PREPARING', version: 2);
        controller.upsertOrder(updated);
        await tester.pumpAndSettle();
        // Items and notes in gray box
        expect(find.text('1 x Seblak Prasmanan'), findsOneWidget);
        expect(find.text('Level 0\nKuah Nyemek'), findsOneWidget);

        // Still only 1 card, not duplicated
        expect(find.byType(OrderQueueCard), findsOneWidget);
        expect(find.text('Sedang Dimasak'), findsAtLeastNWidgets(1));

        // Older event (version 1) is ignored and does not revert or duplicate
        final older = initial.copyWith(version: 1);
        controller.upsertOrder(older);
        await tester.pumpAndSettle();

        expect(find.byType(OrderQueueCard), findsOneWidget);
        expect(find.text('Sedang Dimasak'), findsAtLeastNWidgets(1));
        // Action button for Menunggu tab
        expect(find.text('Mulai Proses'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #3: Overdue alert, drinks highlight, and takeaway notes visible on card',
      'Criteria #3: 1-Tap status transition from Menunggu -> Diproses -> Siap -> Selesai',
      (tester) async {
        final specialOrder = buildOrder(
          id: 'ord-special',
          orderNumber: '#ORD-999',
          customerName: 'Siti Rahma',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PREPARING',
        final order = buildOrder(
          id: 'ord-flow',
          orderNumber: '#ORD-7',
          customerName: 'Budi Santoso',
          source: 'CASHIER_MANUAL',
          orderStatus: 'ACCEPTED',
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
              name: 'Nasi Goreng Gila',
              quantity: 1,
              unitPrice: 28000,
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
          initialOrders: [order],
          timeOverride: fixedNow,
        );

        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        // 1. Overdue alert banner
        expect(
          find.text('TERLAMBAT (> 15 MENIT BELUM SELESAI)'),
          findsOneWidget,
        );
        // 1. Initially in "Menunggu" tab
        expect(find.text('Antrean 7'), findsOneWidget);
        expect(find.text('Mulai Proses'), findsOneWidget);

        // 2. Takeaway notes
        expect(find.text('Pesanan Dibungkus (Takeaway)'), findsOneWidget);
        expect(
          find.text('Catatan Bungkus: Pisah sambal & tanpa sendok'),
          findsOneWidget,
        );
        // 2. Tap "Mulai Proses" -> moves to Diproses
        await tester.tap(find.text('Mulai Proses'));
        await tester.pumpAndSettle();

        // 3. Drinks section
        expect(find.text('Minuman / Barista'), findsOneWidget);
        expect(
          find.text('2x Es Teh Manis Jumbo (Sedikit es batu)'),
          findsOneWidget,
        );
        // Order is no longer in Menunggu tab
        expect(find.text('Tidak Ada Pesanan'), findsOneWidget);

        // 4. Food section
        expect(find.text('2x Nasi Goreng Spesial'), findsOneWidget);
        expect(find.text('Catatan: Pedas level 2'), findsOneWidget);
        // Switch to "Diproses" tab
        await tester.tap(find.text('Diproses'));
        await tester.pumpAndSettle();

        // 5. Total
        expect(find.text('Rp 72000'), findsOneWidget);
        expect(find.text('Antrean 7'), findsOneWidget);
        expect(find.text('Siap Diambil'), findsOneWidget);

        // 3. Tap "Siap Diambil" -> moves to Siap
        await tester.tap(find.text('Siap Diambil'));
        await tester.pumpAndSettle();

        // Order leaves Diproses tab
        expect(find.text('Tidak Ada Pesanan'), findsOneWidget);

        // Switch to "Siap" tab
        await tester.tap(find.text('Siap'));
        await tester.pumpAndSettle();

        expect(find.text('Antrean 7'), findsOneWidget);
        expect(find.text('Selesai'), findsOneWidget);

        // 4. Tap "Selesai" -> completes order
        await tester.tap(find.text('Selesai'));
        await tester.pumpAndSettle();

        // Completed order leaves Siap tab
        expect(find.text('Tidak Ada Pesanan'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #4: Stable sorting prioritizes overdue, PENDING FIFO, and recovery preserves order',
      'Criteria #4: Overdue orders (> 15m) display overdue banner and take priority',
      (tester) async {
        final normalPending = buildOrder(
          id: 'ord-norm-pending',
          orderNumber: '#ORD-001',
          customerName: 'Normal Pending',
        final normalOrder = buildOrder(
          id: 'ord-normal',
          orderNumber: '#ORD-10',
          customerName: 'Normal',
          source: 'WHATSAPP',
          orderStatus: 'PENDING',
          orderStatus: 'ACCEPTED',
          paymentStatus: 'PAID',
          minutesAgo: 5,
        );

        final olderPending = buildOrder(
          id: 'ord-old-pending',
          orderNumber: '#ORD-002',
          customerName: 'Older Pending',
          source: 'CUSTOMER_WEB',
          orderStatus: 'PENDING',
        final overdueOrder = buildOrder(
          id: 'ord-late',
          orderNumber: '#ORD-20',
          customerName: 'Late',
          source: 'WHATSAPP',
          orderStatus: 'ACCEPTED',
          paymentStatus: 'PAID',
          minutesAgo: 10,
          minutesAgo: 18, // > 15 minutes overdue
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
          initialOrders: [normalOrder, overdueOrder],
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
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

        // Simulate recovery snapshot reconnect
        controller.setSnapshot([
          normalPending,
          overduePreparing,
          readyOrder,
          olderPending,
        ], isStale: false);
        // Overdue banner
        expect(
          find.text('TERLAMBAT (> 15 MENIT BELUM SELESAI)'),
          findsOneWidget,
        );

        final recoveredSorted = controller.filteredOrders;
        expect(recoveredSorted[0].id, equals('ord-overdue-prep'));
        expect(recoveredSorted[1].id, equals('ord-old-pending'));
        expect(recoveredSorted[2].id, equals('ord-norm-pending'));
        expect(recoveredSorted[3].id, equals('ord-ready'));
        // Verify order priority: late order card appears first
        final cards = tester.widgetList<OrderQueueCard>(
          find.byType(OrderQueueCard),
        );
        expect(cards.first.order.id, equals('ord-late'));
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
    testWidgets(
      'Criteria #5: Real-time upsert updates existing cards without duplication',
      (tester) async {
        final initial = buildOrder(
          id: 'ord-dup',
          orderNumber: '#ORD-DUP',
          customerName: 'Budi Santoso',
          source: 'CUSTOMER_WEB',
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
          paymentStatus: 'UNPAID',
          version: 1,
        );

      final controller = QueueController(
        initialOrders: orders,
        timeOverride: fixedNow,
      );
      await tester.pumpWidget(buildQueueTestApp(controller));
      await tester.pumpAndSettle();
        final controller = QueueController(
          initialOrders: [initial],
          timeOverride: fixedNow,
        );
        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();

      expect(find.text('#ORD-W1'), findsOneWidget);
      expect(find.text('#ORD-C1'), findsOneWidget);
        expect(find.byType(OrderQueueCard), findsOneWidget);

      // Tap filter status 'Menunggu'
      await tester.tap(find.text('Menunggu (1)'));
      await tester.pumpAndSettle();
        // Upsert updated order
        final updated = initial.copyWith(
          customerName: 'Budi Santoso Updated',
          version: 2,
        );
        controller.upsertOrder(updated);
        await tester.pumpAndSettle();

      expect(find.text('#ORD-W1'), findsOneWidget);
      expect(find.text('#ORD-C1'), findsNothing);
        expect(find.byType(OrderQueueCard), findsOneWidget);
      },
    );

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
      'Criteria #6: Presentation states (Loading, Empty per tab, Error, Stale banner)',
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
        // 4. Stale / Offline state
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
      'Criteria #7: Responsive layout renders without overflow on mobile and tablet',
      (tester) async {
        final orders = List.generate(4, (i) {
          return buildOrder(
            id: 'ord-resp-$i',
            orderNumber: '#ORD-R$i',
            orderNumber: '#ORD-$i',
            customerName: 'Pelanggan $i',
            source: i % 2 == 0 ? 'WHATSAPP' : 'CUSTOMER_WEB',
            orderStatus: i % 2 == 0 ? 'PENDING' : 'PREPARING',
            orderStatus: 'ACCEPTED',
            paymentStatus: 'PAID',
            isTakeaway: true,
            takeawayNotes: 'Bungkus rapi $i',
            isTakeaway: i % 2 == 0,
            items: [
              QueueOrderItem(
                name: 'Nasi Goreng $i',
                quantity: 1,
                unitPrice: 25000,
                name: 'Menu $i',
                quantity: i + 1,
                unitPrice: 20000,
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
        // Mobile viewport
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildQueueTestApp(controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Test tablet viewport
        // Tablet viewport
        tester.view.physicalSize = const Size(1024, 768);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
