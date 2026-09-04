import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pesenhub_app/core/utils/event_deduplicator.dart';
import 'package:pesenhub_app/data/local/conflict_audit_repository.dart';
import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/order/controllers/order_detail_controller.dart';
import 'package:pesenhub_app/order/models/order_conflict.dart';
import 'package:pesenhub_app/order/models/order_timeline_event.dart';
import 'package:pesenhub_app/order/order_detail_view.dart';
import 'package:pesenhub_app/order/widgets/conflict_resolution_dialog.dart';
import 'package:pesenhub_app/queue/controllers/queue_controller.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Acceptance Criteria #1: Stale Mutation Conflict & Server-Wins Protection', () {
    test('Server-wins protects terminal state (COMPLETED) against stale local update', () {
      final localOrder = QueueOrder(
        id: 'ord-1',
        orderNumber: 'ORD-001',
        customerName: 'Budi',
        customerPhone: '0812****5678',
        source: 'CASHIER_MANUAL',
        orderStatus: 'PREPARING',
        paymentStatus: 'UNPAID',
        items: [QueueOrderItem(name: 'Nasi Goreng', quantity: 1, unitPrice: 20000)],
        createdAt: DateTime(2026),
        version: 1,
      );

      final serverOrder = QueueOrder(
        id: 'ord-1',
        orderNumber: 'ORD-001',
        customerName: 'Budi',
        customerPhone: '0812****5678',
        source: 'CASHIER_MANUAL',
        orderStatus: 'COMPLETED',
        paymentStatus: 'PAID',
        items: [QueueOrderItem(name: 'Nasi Goreng', quantity: 1, unitPrice: 20000)],
        createdAt: DateTime(2026),
        version: 2,
      );

      final classification = ConflictClassifier.classify(
        localOrder: localOrder,
        serverOrder: serverOrder,
      );

      expect(classification.type, equals(ConflictType.unsafeFinalState));
      expect(classification.isSafe, isFalse);
      expect(classification.enforcesServerWins, isTrue);
      expect(classification.defaultStrategy, equals(ResolutionStrategy.serverWins));

      final resolved = ConflictResolver.resolve(
        classification: classification,
        strategy: ResolutionStrategy.serverWins,
      );
      expect(resolved.orderStatus, equals('COMPLETED'));
      expect(resolved.paymentStatus, equals('PAID'));
      expect(resolved.version, equals(2));
    });

    test('Server-wins protects PAID status against local UNPAID state', () {
      final localOrder = QueueOrder(
        id: 'ord-2',
        orderNumber: 'ORD-002',
        customerName: 'Siti',
        customerPhone: '0813****1234',
        source: 'CUSTOMER_WEB',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        items: [QueueOrderItem(name: 'Mie Goreng', quantity: 1, unitPrice: 18000)],
        createdAt: DateTime(2026),
        version: 1,
      );

      final serverOrder = QueueOrder(
        id: 'ord-2',
        orderNumber: 'ORD-002',
        customerName: 'Siti',
        customerPhone: '0813****1234',
        source: 'CUSTOMER_WEB',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'PAID', // Server webhook confirmed payment
        items: [QueueOrderItem(name: 'Mie Goreng', quantity: 1, unitPrice: 18000)],
        createdAt: DateTime(2026),
        version: 2,
      );

      final classification = ConflictClassifier.classify(
        localOrder: localOrder,
        serverOrder: serverOrder,
      );

      expect(classification.type, equals(ConflictType.unsafePaymentMismatch));
      expect(classification.isSafe, isFalse);
      expect(classification.enforcesServerWins, isTrue);

      final resolved = ConflictResolver.resolve(
        classification: classification,
        strategy: ResolutionStrategy.serverWins,
      );
      expect(resolved.paymentStatus, equals('PAID'));
    });

    test('QueueController rejects regression of terminal orders and PAID status', () {
      final controller = QueueController();
      final serverOrder = QueueOrder(
        id: 'ord-3',
        orderNumber: 'ORD-003',
        customerName: 'Ahmad',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'COMPLETED',
        paymentStatus: 'PAID',
        items: [],
        createdAt: DateTime(2026),
        version: 3,
      );
      controller.upsertOrder(serverOrder);
      expect(controller.allOrders.first.orderStatus, equals('COMPLETED'));

      // 1. Incoming event trying to regress status to PREPARING is ignored
      final staleEvent = serverOrder.copyWith(orderStatus: 'PREPARING', version: 4);
      controller.upsertOrder(staleEvent);
      expect(controller.allOrders.first.orderStatus, equals('COMPLETED')); // Kept COMPLETED

      // 2. Local update attempt on completed order returns false
      final updateSuccess = controller.updateOrderStatus('ord-3', 'PREPARING');
      expect(updateSuccess, isFalse);
      expect(controller.allOrders.first.orderStatus, equals('COMPLETED'));
    });
  });

  group('Acceptance Criteria #2: Duplicate Ack and Event Prevention', () {
    test('EventDeduplicator filters duplicate event IDs within bounded capacity', () {
      final dedupe = EventDeduplicator(maxCapacity: 3);

      expect(dedupe.shouldProcess('evt-1'), isTrue);
      expect(dedupe.shouldProcess('evt-1'), isFalse); // Duplicate
      expect(dedupe.shouldProcess('evt-2'), isTrue);
      expect(dedupe.shouldProcess('evt-3'), isTrue);

      // Cache size is 3
      expect(dedupe.size, equals(3));

      // Adding 4th evicts evt-1
      expect(dedupe.shouldProcess('evt-4'), isTrue);
      expect(dedupe.size, equals(3));
      expect(dedupe.isDuplicate('evt-1'), isFalse); // Evicted
      expect(dedupe.isDuplicate('evt-4'), isTrue);
    });

    test('QueueController with duplicate eventId drops redundant processing', () {
      final controller = QueueController();
      final order = QueueOrder(
        id: 'ord-10',
        orderNumber: 'ORD-010',
        customerName: 'Dewi',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        items: [],
        createdAt: DateTime(2026),
        version: 1,
      );

      controller.upsertOrder(order, eventId: 'event-unique-1');
      expect(controller.totalCount, equals(1));

      // Duplicate delivery of same event
      controller.upsertOrder(order, eventId: 'event-unique-1');
      expect(controller.totalCount, equals(1));
    });

    test('OrderTimelineEvent.deduplicate removes duplicate events and preserves chronological sequence', () {
      final now = DateTime(2026, 9, 4, 10, 0);
      final rawEvents = [
        OrderTimelineEvent(
          id: 'evt-1',
          orderId: 'ord-1',
          status: 'ACCEPTED',
          actor: 'STAFF',
          timestamp: now,
          version: 1,
        ),
        // Exact duplicate event ID
        OrderTimelineEvent(
          id: 'evt-1',
          orderId: 'ord-1',
          status: 'ACCEPTED',
          actor: 'STAFF',
          timestamp: now,
          version: 1,
        ),
        // Milestone duplicate: repeated same status at same version
        OrderTimelineEvent(
          id: 'evt-2',
          orderId: 'ord-1',
          status: 'ACCEPTED',
          actor: 'STAFF',
          timestamp: now.add(const Duration(seconds: 1)),
          version: 1,
        ),
        OrderTimelineEvent(
          id: 'evt-3',
          orderId: 'ord-1',
          status: 'PREPARING',
          actor: 'KDS',
          timestamp: now.add(const Duration(minutes: 2)),
          version: 2,
        ),
      ];

      final deduplicated = OrderTimelineEvent.deduplicate(rawEvents);
      expect(deduplicated.length, equals(2));
      expect(deduplicated[0].status, equals('ACCEPTED'));
      expect(deduplicated[1].status, equals('PREPARING'));
    });
  });

  group('Acceptance Criteria #3: Safe vs Unsafe Conflict Resolution Strategies', () {
    test('Safe conflict allows clientWins, serverWins, and merge strategies', () {
      final localOrder = QueueOrder(
        id: 'ord-safe',
        orderNumber: 'ORD-SAFE',
        customerName: 'Hendra',
        customerPhone: '0812****1111',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        takeawayNotes: 'Bungkus terpisah ya',
        isTakeaway: true,
        items: [],
        createdAt: DateTime(2026),
        version: 2,
      );

      final serverOrder = QueueOrder(
        id: 'ord-safe',
        orderNumber: 'ORD-SAFE',
        customerName: 'Hendra',
        customerPhone: '0812****1111',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        takeawayNotes: 'Pedas level 5',
        isTakeaway: false,
        items: [],
        createdAt: DateTime(2026),
        version: 2,
      );

      final classification = ConflictClassifier.classify(
        localOrder: localOrder,
        serverOrder: serverOrder,
      );

      expect(classification.isSafe, isTrue);
      expect(classification.type, equals(ConflictType.safeEditableField));
      expect(
        classification.allowedStrategies,
        containsAll([
          ResolutionStrategy.clientWins,
          ResolutionStrategy.serverWins,
          ResolutionStrategy.merge,
        ]),
      );

      // 1. Client wins
      final clientResolved = ConflictResolver.resolve(
        classification: classification,
        strategy: ResolutionStrategy.clientWins,
      );
      expect(clientResolved.takeawayNotes, equals('Bungkus terpisah ya'));
      expect(clientResolved.version, equals(3));

      // 2. Server wins
      final serverResolved = ConflictResolver.resolve(
        classification: classification,
        strategy: ResolutionStrategy.serverWins,
      );
      expect(serverResolved.takeawayNotes, equals('Pedas level 5'));
      expect(serverResolved.version, equals(2));

      // 3. Merge
      final mergeResolved = ConflictResolver.resolve(
        classification: classification,
        strategy: ResolutionStrategy.merge,
      );
      expect(mergeResolved.takeawayNotes, contains('Pedas level 5 | [Lokal: Bungkus terpisah ya]'));
      expect(mergeResolved.isTakeaway, isTrue);
      expect(mergeResolved.version, equals(3));
    });

    test('Unsafe conflict prevents clientWins override and defaults to serverWins', () {
      final localOrder = QueueOrder(
        id: 'ord-unsafe',
        orderNumber: 'ORD-UNSAFE',
        customerName: 'Maya',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'PREPARING',
        paymentStatus: 'UNPAID',
        items: [],
        createdAt: DateTime(2026),
        version: 1,
      );

      final serverOrder = QueueOrder(
        id: 'ord-unsafe',
        orderNumber: 'ORD-UNSAFE',
        customerName: 'Maya',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'COMPLETED',
        paymentStatus: 'PAID',
        items: [],
        createdAt: DateTime(2026),
        version: 3,
      );

      final classification = ConflictClassifier.classify(
        localOrder: localOrder,
        serverOrder: serverOrder,
      );

      expect(classification.isSafe, isFalse);

      // Attempting clientWins on unsafe conflict safely falls back to server
      final forced = ConflictResolver.resolve(
        classification: classification,
        strategy: ResolutionStrategy.clientWins,
      );
      expect(forced.orderStatus, equals('COMPLETED'));
      expect(forced.paymentStatus, equals('PAID'));
    });
  });

  group('Acceptance Criteria #4: Conflict Audit Logging without Sensitive PII', () {
    late LocalDatabase localDb;
    late ConflictAuditRepository auditRepo;

    setUp(() async {
      final dbPath = p.join(
        await databaseFactoryFfi.getDatabasesPath(),
        'test_conflict_audit_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      localDb = LocalDatabase(customPath: dbPath);
      await localDb.clearAllData();
      auditRepo = ConflictAuditRepository(localDb: localDb);
    });

    tearDown(() async {
      await localDb.close();
    });

    test('logConflict masks customer phone and records resolution without PII', () async {
      await auditRepo.logConflict(
        id: 'conflict-entry-1',
        orderId: 'ord-audit-1',
        clientOrderId: 'client-audit-1',
        conflictType: 'safeEditableField',
        resolutionStrategy: 'merge',
        clientVersion: 2,
        serverVersion: 3,
        resolvedPayload: {
          'order_status': 'ACCEPTED',
          'customer_name': 'Bapak Joko',
          'customer_phone': '081234567890', // Raw phone must be masked!
          'takeaway_notes': 'Merged notes',
        },
        notes: 'Merged local and server notes',
      );

      final logs = await auditRepo.getConflictLogsForOrder('ord-audit-1');
      expect(logs.length, equals(1));

      final logged = logs.first;
      expect(logged.conflictType, equals('safeEditableField'));
      expect(logged.resolutionStrategy, equals('merge'));
      expect(logged.clientVersion, equals(2));
      expect(logged.serverVersion, equals(3));

      // Invariant 11: Phone number in payload is masked
      expect(logged.resolvedPayloadJson, contains('0812****7890'));
      expect(logged.resolvedPayloadJson, isNot(contains('081234567890')));
    });

    test('QueueController.applyConflictResolution records audit entry automatically', () async {
      final controller = QueueController();
      final local = QueueOrder(
        id: 'ord-audit-2',
        orderNumber: 'ORD-02',
        customerName: 'Joko',
        customerPhone: '081987654321',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        takeawayNotes: 'Note local',
        items: [],
        createdAt: DateTime(2026),
        version: 1,
      );

      final server = QueueOrder(
        id: 'ord-audit-2',
        orderNumber: 'ORD-02',
        customerName: 'Joko',
        customerPhone: '081987654321',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        takeawayNotes: 'Note server',
        items: [],
        createdAt: DateTime(2026),
        version: 2,
      );

      final classification = ConflictClassifier.classify(
        localOrder: local,
        serverOrder: server,
      );

      final resolved = await controller.applyConflictResolution(
        classification: classification,
        strategy: ResolutionStrategy.merge,
        auditRepo: auditRepo,
      );

      expect(resolved.takeawayNotes, contains('Note server | [Lokal: Note local]'));

      final recordedLogs = await auditRepo.getAllConflictLogs();
      expect(recordedLogs.length, equals(1));
      expect(recordedLogs.first.orderId, equals('ord-audit-2'));
      expect(recordedLogs.first.resolutionStrategy, equals('merge'));
    });
  });

  group('Acceptance Criteria #5: Responsive UI States on Mobile & Tablet', () {
    testWidgets('ConflictResolutionDialog renders safe conflict on mobile (390 x 844) without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      ResolutionStrategy? chosen;
      final local = QueueOrder(
        id: 'ord-ui-1',
        orderNumber: 'ORD-UI-1',
        customerName: 'Rian',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        takeawayNotes: 'Lokal: jangan pedas',
        items: [],
        createdAt: DateTime(2026),
        version: 1,
      );
      final server = QueueOrder(
        id: 'ord-ui-1',
        orderNumber: 'ORD-UI-1',
        customerName: 'Rian',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        takeawayNotes: 'Server: pedas sedang',
        items: [],
        createdAt: DateTime(2026),
        version: 2,
      );

      final classification = ConflictClassifier.classify(
        localOrder: local,
        serverOrder: server,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictResolutionDialog(
              classification: classification,
              onResolve: (strategy) => chosen = strategy,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Resolusi Konflik Data'), findsOneWidget);
      expect(find.text('Gunakan Versi Server'), findsOneWidget);
      expect(find.text('Pertahankan Perubahan Lokal'), findsOneWidget);
      expect(find.text('Gabungkan Catatan'), findsOneWidget);

      await tester.tap(find.text('Pertahankan Perubahan Lokal'));
      await tester.pump();
      expect(chosen, equals(ResolutionStrategy.clientWins));
    });

    testWidgets('ConflictResolutionDialog renders unsafe conflict on tablet (1024 x 768) without overflow', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      ResolutionStrategy? chosen;
      final local = QueueOrder(
        id: 'ord-ui-2',
        orderNumber: 'ORD-UI-2',
        customerName: 'Rian',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        items: [],
        createdAt: DateTime(2026),
        version: 1,
      );
      final server = QueueOrder(
        id: 'ord-ui-2',
        orderNumber: 'ORD-UI-2',
        customerName: 'Rian',
        customerPhone: '',
        source: 'CASHIER_MANUAL',
        orderStatus: 'COMPLETED',
        paymentStatus: 'PAID',
        items: [],
        createdAt: DateTime(2026),
        version: 3,
      );

      final classification = ConflictClassifier.classify(
        localOrder: local,
        serverOrder: server,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictResolutionDialog(
              classification: classification,
              onResolve: (strategy) => chosen = strategy,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Pembaruan Server Wajib (Server-Wins)'), findsOneWidget);
      expect(find.text('Muat Ulang Data Server'), findsOneWidget);

      await tester.tap(find.text('Muat Ulang Data Server'));
      await tester.pump();
      expect(chosen, equals(ResolutionStrategy.forceReload));
    });

    testWidgets('OrderDetailView displays conflict banner and resolution triggers', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final order = QueueOrder(
        id: 'ord-view-1',
        orderNumber: 'ORD-VIEW-1',
        customerName: 'Bambang',
        customerPhone: '0812****9999',
        source: 'CASHIER_MANUAL',
        orderStatus: 'ACCEPTED',
        paymentStatus: 'UNPAID',
        takeawayNotes: 'Lokal: extra kerupuk',
        items: [],
        createdAt: DateTime(2026),
        version: 1,
      );

      final controller = OrderDetailController(initialOrder: order);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderDetailView(
              controller: controller,
              reloadFn: (id) async {
                return order.copyWith(
                  takeawayNotes: 'Server: tanpa kerupuk',
                  version: 2,
                );
              },
            ),
          ),
        ),
      );

      // Simulate conflict triggered via executeAction error
      await controller.executeAction(
        controller.primaryAction!,
        transitionFn: (id, status, ver) async => throw Exception('409 VERSION_CONFLICT'),
        reloadFn: (id) async => order.copyWith(
          takeawayNotes: 'Server: tanpa kerupuk',
          version: 2,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pilih Resolusi Konflik'), findsOneWidget);
      expect(find.text('Muat Ulang Data Terbaru'), findsOneWidget);
    });
  });
}
