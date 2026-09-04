import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pesenhub_app/cart/controllers/cart_controller.dart';
import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/data/local/models/outbox_mutation.dart';
import 'package:pesenhub_app/data/local/outbox_repository.dart';
import 'package:pesenhub_app/data/local/queue_local_repository.dart';
import 'package:pesenhub_app/data/sync/sync_service.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:pesenhub_app/widgets/sync_status_badge.dart';

/// Fake test gateway for controllable sync responses.
class FakeOrderSyncGateway implements OrderSyncGateway {
  SyncGatewayResponse Function(String idempotencyKey, String payloadJson)?
  onSubmit;

  final List<String> submittedIdempotencyKeys = [];

  @override
  Future<SyncGatewayResponse> submitOrderMutation({
    required String idempotencyKey,
    required String payloadJson,
  }) async {
    submittedIdempotencyKeys.add(idempotencyKey);
    if (onSubmit != null) {
      return onSubmit!(idempotencyKey, payloadJson);
    }
    return SyncGatewayResponse.success(serverOrderId: 'srv-$idempotencyKey');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group(
    'Acceptance Criteria #1: Offline Manual Order Persists Locally with PENDING Status',
    () {
      late LocalDatabase localDb;
      late QueueLocalRepository queueRepo;
      late OutboxRepository outboxRepo;
      late CartController cartController;

      setUp(() async {
        localDb = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        queueRepo = QueueLocalRepository(localDb);
        outboxRepo = OutboxRepository(localDb);
        cartController = CartController();
      });

      tearDown(() async {
        await localDb.close();
      });

      test(
        'submitOfflineOrder saves local queue order as PENDING and enqueues OutboxMutation',
        () async {
          // Setup cart with customer and item
          cartController.setCustomerName('Pak Bambang');
          cartController.setCustomerPhone('081234567890');
          cartController.addItem(
            const MenuItem(
              id: 'menu-1',
              categoryId: 'cat-1',
              sku: 'NASGOR-01',
              name: 'Nasi Goreng Spesial',
              priceAmount: 25000,
            ),
          );

          final submittedClientOrderId = cartController.clientOrderId;
          final result = await cartController.submitOfflineOrder(
            outboxRepo: outboxRepo,
            queueRepo: queueRepo,
          );

          expect(result, isNotNull);
          expect(result!.orderStatus, equals('PENDING'));
          expect(result.paymentStatus, equals('UNPAID'));
          expect(result.source, equals('CASHIER_MANUAL'));
          expect(result.customerPhone, equals('0812****7890')); // PII masked

          // Check order in local SQLite queue
          final storedOrders = await queueRepo.getOrders();
          expect(storedOrders.length, equals(1));
          expect(storedOrders.first.id, equals(result.id));
          expect(storedOrders.first.id, equals('ord-$submittedClientOrderId'));
          expect(storedOrders.first.orderStatus, equals('PENDING'));

          // Check mutation in SQLite outbox
          final mutations = await outboxRepo.getAllMutations();
          expect(mutations.length, equals(1));
          expect(mutations.first.clientOrderId, equals(submittedClientOrderId));
          expect(
            cartController.clientOrderId,
            isNot(equals(submittedClientOrderId)),
          );
          expect(mutations.first.syncStatus, equals(OutboxSyncStatus.pending));
          expect(mutations.first.payloadJson, contains('Pak Bambang'));
        },
      );
    },
  );

  group('Acceptance Criteria #2: Durable Outbox Across App Restart', () {
    test(
      'Preserves pending outbox mutations after database close and reopen',
      () async {
        final dbFolder = await databaseFactoryFfi.getDatabasesPath();
        final durableDbPath = p.join(dbFolder, 'test_durable_outbox.db');
        await databaseFactoryFfi.deleteDatabase(durableDbPath);

        // Session 1: App creates offline orders
        final session1Db = LocalDatabase(
          customPath: durableDbPath,
          customFactory: databaseFactoryFfi,
        );
        final outboxRepo1 = OutboxRepository(session1Db);

        final mutation1 = OutboxMutation(
          id: 'mut-001',
          idempotencyKey: 'idem-key-001',
          clientOrderId: 'client-order-001',
          payloadJson: '{"customer_name":"Ibu Sri","total":35000}',
          syncStatus: OutboxSyncStatus.pending,
          createdAt: DateTime.now(),
        );

        final mutation2 = OutboxMutation(
          id: 'mut-002',
          idempotencyKey: 'idem-key-002',
          clientOrderId: 'client-order-002',
          payloadJson: '{"customer_name":"Pak Hendra","total":28000}',
          syncStatus: OutboxSyncStatus.pending,
          createdAt: DateTime.now(),
        );

        await outboxRepo1.enqueueMutation(mutation1);
        await outboxRepo1.enqueueMutation(mutation2);

        expect(await outboxRepo1.getPendingCount(), equals(2));

        // Simulate App Kill / Process Exit
        await session1Db.close();

        // Session 2: App Starts Up / Reconnects
        final session2Db = LocalDatabase(
          customPath: durableDbPath,
          customFactory: databaseFactoryFfi,
        );
        final outboxRepo2 = OutboxRepository(session2Db);

        final recoveredMutations = await outboxRepo2.getAllMutations();
        expect(recoveredMutations.length, equals(2));

        final first = recoveredMutations.firstWhere((m) => m.id == 'mut-001');
        expect(first.idempotencyKey, equals('idem-key-001'));
        expect(first.clientOrderId, equals('client-order-001'));
        expect(first.syncStatus, equals(OutboxSyncStatus.pending));
        expect(first.payloadJson, contains('Ibu Sri'));

        final second = recoveredMutations.firstWhere((m) => m.id == 'mut-002');
        expect(second.idempotencyKey, equals('idem-key-002'));
        expect(second.syncStatus, equals(OutboxSyncStatus.pending));

        await session2Db.close();
        await databaseFactoryFfi.deleteDatabase(durableDbPath);
      },
    );
  });

  group(
    'Acceptance Criteria #3: Reconnect Syncs to ACK Without Duplicate Orders',
    () {
      late LocalDatabase localDb;
      late QueueLocalRepository queueRepo;
      late OutboxRepository outboxRepo;
      late FakeOrderSyncGateway fakeGateway;
      late SyncService syncService;

      setUp(() {
        localDb = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        queueRepo = QueueLocalRepository(localDb);
        outboxRepo = OutboxRepository(localDb);
        fakeGateway = FakeOrderSyncGateway();
        syncService = SyncService(
          outboxRepo: outboxRepo,
          queueRepo: queueRepo,
          gateway: fakeGateway,
        );
      });

      tearDown(() async {
        await localDb.close();
      });

      test('Syncs mutations sequentially and records server ACK', () async {
        await outboxRepo.enqueueMutation(
          OutboxMutation(
            id: 'mut-seq-1',
            idempotencyKey: 'idem-101',
            clientOrderId: 'ord-101',
            payloadJson: '{"customer_name":"Order 1"}',
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        );
        await outboxRepo.enqueueMutation(
          OutboxMutation(
            id: 'mut-seq-2',
            idempotencyKey: 'idem-102',
            clientOrderId: 'ord-102',
            payloadJson: '{"customer_name":"Order 2"}',
            createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
          ),
        );

        final result = await syncService.syncPendingMutations();

        expect(result.totalProcessed, equals(2));
        expect(result.syncedCount, equals(2));
        expect(result.hasErrors, isFalse);
        expect(await outboxRepo.getPendingCount(), equals(0));

        final allMutations = await outboxRepo.getAllMutations();
        expect(
          allMutations.every((m) => m.syncStatus == OutboxSyncStatus.synced),
          isTrue,
        );
        expect(allMutations.first.serverOrderId, equals('srv-idem-101'));
        expect(allMutations.last.serverOrderId, equals('srv-idem-102'));
      });

      test(
        'Idempotent replay (409 Conflict) acks existing server order without duplication',
        () async {
          await outboxRepo.enqueueMutation(
            OutboxMutation(
              id: 'mut-replay-1',
              idempotencyKey: 'idem-conflict-1',
              clientOrderId: 'ord-replay-1',
              payloadJson: '{"customer_name":"Order Replay"}',
              createdAt: DateTime.now(),
            ),
          );

          // Server returns already created order for this idempotency key
          fakeGateway.onSubmit = (key, payload) {
            return const SyncGatewayResponse.success(
              serverOrderId: 'srv-already-created-999',
              isDuplicate: true,
            );
          };

          final result = await syncService.syncPendingMutations();

          expect(result.syncedCount, equals(1));
          expect(result.hasErrors, isFalse);

          final mutation = await outboxRepo.getByClientOrderId('ord-replay-1');
          expect(mutation!.syncStatus, equals(OutboxSyncStatus.synced));
          expect(mutation.serverOrderId, equals('srv-already-created-999'));
        },
      );
    },
  );

  group(
    'Acceptance Criteria #4: Transient Retry with Backoff & Permanent Validation Failure',
    () {
      late LocalDatabase localDb;
      late QueueLocalRepository queueRepo;
      late OutboxRepository outboxRepo;
      late FakeOrderSyncGateway fakeGateway;
      late SyncService syncService;

      setUp(() {
        localDb = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        queueRepo = QueueLocalRepository(localDb);
        outboxRepo = OutboxRepository(localDb);
        fakeGateway = FakeOrderSyncGateway();
        syncService = SyncService(
          outboxRepo: outboxRepo,
          queueRepo: queueRepo,
          gateway: fakeGateway,
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 60),
        );
      });

      tearDown(() async {
        await localDb.close();
      });

      test('Calculates exponential backoff delay correctly', () {
        expect(
          syncService.calculateBackoff(0),
          equals(const Duration(seconds: 1)),
        );
        expect(
          syncService.calculateBackoff(1),
          equals(const Duration(seconds: 2)),
        );
        expect(
          syncService.calculateBackoff(2),
          equals(const Duration(seconds: 4)),
        );
        expect(
          syncService.calculateBackoff(3),
          equals(const Duration(seconds: 8)),
        );
        expect(
          syncService.calculateBackoff(4),
          equals(const Duration(seconds: 16)),
        );
        expect(
          syncService.calculateBackoff(5),
          equals(const Duration(seconds: 32)),
        );
        expect(
          syncService.calculateBackoff(6),
          equals(const Duration(seconds: 60)),
        ); // Capped at maxDelay
        expect(
          syncService.calculateBackoff(10),
          equals(const Duration(seconds: 60)),
        );
      });

      test(
        'Transient failure increments retry count and sets next_retry_at',
        () async {
          await outboxRepo.enqueueMutation(
            OutboxMutation(
              id: 'mut-transient-1',
              idempotencyKey: 'idem-transient-1',
              clientOrderId: 'ord-transient-1',
              payloadJson: '{"customer_name":"Test"}',
              createdAt: DateTime.now(),
            ),
          );

          // Simulate transient 503 error
          fakeGateway.onSubmit = (key, payload) {
            return const SyncGatewayResponse.transientError(
              errorMessage: '503 Service Unavailable',
            );
          };

          final result = await syncService.syncPendingMutations();

          expect(result.transientErrorCount, equals(1));
          expect(result.syncedCount, equals(0));

          final mutation = await outboxRepo.getByClientOrderId(
            'ord-transient-1',
          );
          expect(
            mutation!.syncStatus,
            equals(OutboxSyncStatus.failedTransient),
          );
          expect(mutation.retryCount, equals(1));
          expect(mutation.nextRetryAt, isNotNull);
          expect(mutation.nextRetryAt!.isAfter(DateTime.now()), isTrue);
          expect(mutation.errorMessage, equals('503 Service Unavailable'));
        },
      );

      test(
        'Permanent validation error stops retry and marks FAILED_PERMANENT',
        () async {
          await outboxRepo.enqueueMutation(
            OutboxMutation(
              id: 'mut-perm-1',
              idempotencyKey: 'idem-perm-1',
              clientOrderId: 'ord-perm-1',
              payloadJson: '{"customer_name":""}',
              createdAt: DateTime.now(),
            ),
          );

          // Simulate 400 Bad Request
          fakeGateway.onSubmit = (key, payload) {
            return const SyncGatewayResponse.permanentError(
              errorMessage: '400 Bad Request: customer name is required',
            );
          };

          final result = await syncService.syncPendingMutations();

          expect(result.permanentErrorCount, equals(1));
          expect(result.transientErrorCount, equals(0));

          final mutation = await outboxRepo.getByClientOrderId('ord-perm-1');
          expect(
            mutation!.syncStatus,
            equals(OutboxSyncStatus.failedPermanent),
          );
          expect(mutation.nextRetryAt, isNull);
          expect(mutation.errorMessage, contains('400 Bad Request'));

          // Subsequent sync does NOT re-process permanent failure
          final secondSync = await syncService.syncPendingMutations();
          expect(secondSync.totalProcessed, equals(0));
        },
      );
    },
  );

  group('Acceptance Criteria #5: Responsive UI States on Mobile & Tablet', () {
    testWidgets('Renders idle / synced state cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SyncStatusBadge(
              state: SyncServiceState(pendingCount: 0, isSyncing: false),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('sync-status-idle')), findsOneWidget);
      expect(find.text('Tersinkron'), findsOneWidget);
    });

    testWidgets('Renders syncing progress state with spinner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SyncStatusBadge(
              state: SyncServiceState(pendingCount: 3, isSyncing: true),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('sync-status-syncing')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Menyinkronkan (3)...'), findsOneWidget);
    });

    testWidgets(
      'Renders pending offline count badge and triggers sync on tap',
      (tester) async {
        bool syncTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SyncStatusBadge(
                state: const SyncServiceState(
                  pendingCount: 4,
                  isSyncing: false,
                ),
                onTriggerSync: () => syncTapped = true,
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('sync-status-pending')), findsOneWidget);
        expect(find.text('4 Offline Antre'), findsOneWidget);

        await tester.tap(find.byKey(const Key('sync-status-pending')));
        await tester.pump();
        expect(syncTapped, isTrue);
      },
    );

    testWidgets(
      'Renders permanent error alert badge and triggers detail view on tap',
      (tester) async {
        bool errorTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SyncStatusBadge(
                state: const SyncServiceState(
                  pendingCount: 1,
                  permanentFailureCount: 1,
                  isSyncing: false,
                ),
                onViewErrors: () => errorTapped = true,
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('sync-status-error')), findsOneWidget);
        expect(find.text('1 Gagal Validasi'), findsOneWidget);

        await tester.tap(find.byKey(const Key('sync-status-error')));
        await tester.pump();
        expect(errorTapped, isTrue);
      },
    );

    testWidgets('Renders without overflow on mobile viewport (390 x 844)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(child: Text('Kasir POS')),
                SyncStatusBadge(
                  state: SyncServiceState(pendingCount: 5, isSyncing: false),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('5 Offline Antre'), findsOneWidget);
    });

    testWidgets('Renders without overflow on tablet viewport (1024 x 768)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(child: Text('KDS Tablet Monitor')),
                SyncStatusBadge(
                  state: SyncServiceState(pendingCount: 12, isSyncing: true),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Menyinkronkan (12)...'), findsOneWidget);
    });
  });
}
