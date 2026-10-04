import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/connectivity/connectivity_controller.dart';
import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/data/local/outbox_repository.dart';
import 'package:pesenhub_app/data/local/queue_local_repository.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/api_failure.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/data/remote/queue_realtime_coordinator.dart';
import 'package:pesenhub_app/data/remote/realtime_connection.dart';
import 'package:pesenhub_app/data/sync/sync_service.dart';
import 'package:pesenhub_app/queue/controllers/queue_controller.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockTestGateway implements QueueRemoteGateway, OrderSyncGateway {
  List<QueueOrder> currentQueue;
  final Map<String, QueueOrder> allOrders = {};
  bool failNextTransition = false;
  String? lastTransitionedId;
  String? lastTransitionedStatus;
  int transitionCalls = 0;

  MockTestGateway(this.currentQueue) {
    for (final o in currentQueue) {
      allOrders[o.id] = o;
    }
  }

  @override
  Future<List<QueueOrder>> fetchQueue() async {
    return List<QueueOrder>.from(currentQueue);
  }

  @override
  Future<QueueOrder> fetchOrder(String id) async {
    final order = allOrders[id];
    if (order == null) {
      throw const ApiFailure(ApiFailureKind.validation);
    }
    return order;
  }

  @override
  Future<QueueOrder> transitionOrderStatus(
    String orderId,
    String targetStatus,
    int expectedVersion, {
    String? reasonCode,
  }) async {
    transitionCalls++;
    if (failNextTransition) {
      throw const ApiFailure(ApiFailureKind.conflict);
    }
    final existing =
        allOrders[orderId] ??
        QueueOrder(
          id: orderId,
          orderNumber: '#TEST',
          customerName: 'Customer',
          customerPhone: '08123456789',
          source: 'CASHIER_MANUAL',
          orderStatus: 'READY_FOR_PICKUP',
          paymentStatus: 'PAID',
          createdAt: DateTime.now(),
          version: expectedVersion,
        );

    final updated = existing.copyWith(
      orderStatus: targetStatus,
      version: expectedVersion + 1,
    );
    allOrders[orderId] = updated;
    lastTransitionedId = orderId;
    lastTransitionedStatus = targetStatus;

    if (targetStatus == 'COMPLETED' ||
        targetStatus == 'CANCELLED' ||
        targetStatus == 'REJECTED') {
      currentQueue.removeWhere((o) => o.id == orderId);
    } else {
      final idx = currentQueue.indexWhere((o) => o.id == orderId);
      if (idx >= 0) {
        currentQueue[idx] = updated;
      } else {
        currentQueue.add(updated);
      }
    }
    return updated;
  }

  @override
  Future<SyncGatewayResponse> submitOrderMutation({
    required String idempotencyKey,
    required String payloadJson,
  }) async {
    return const SyncGatewayResponse.success(serverOrderId: 'ACK-1');
  }
}

class MockRealtimeConnection implements RealtimeConnection {
  final _controller = StreamController<dynamic>.broadcast();

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get messages => _controller.stream;

  void emit(String event) => _controller.add(event);

  @override
  Future<void> close() async => _controller.close();
}

class MockRealtimeFactory implements RealtimeConnectionFactory {
  final connection = MockRealtimeConnection();
  @override
  RealtimeConnection connect(Uri uri) => connection;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final fixedNow = DateTime(2026, 10, 3, 15, 0);

  QueueOrder makeOrder({
    required String id,
    required String orderNumber,
    String status = 'READY_FOR_PICKUP',
    String paymentStatus = 'PAID',
    int version = 1,
  }) {
    return QueueOrder(
      id: id,
      orderNumber: orderNumber,
      customerName: 'Pelanggan Uji',
      customerPhone: '08123456789',
      source: 'CASHIER_MANUAL',
      orderStatus: status,
      paymentStatus: paymentStatus,
      createdAt: fixedNow.subtract(const Duration(minutes: 5)),
      version: version,
      items: const [
        QueueOrderItem(name: 'Martabak Telur', quantity: 1, unitPrice: 35000),
      ],
    );
  }

  group('Fase B: Reproduksi & Regression Tests Transaksi Selesai Muncul Lagi', () {
    test('B4.1: Selesai lalu refresh tidak memunculkan kembali pesanan', () async {
      final initialOrder = makeOrder(
        id: 'ord-101',
        orderNumber: '#ORD-101',
        status: 'READY_FOR_PICKUP',
        version: 1,
      );
      final controller = QueueController(initialOrders: [initialOrder]);
      expect(controller.countForStatus('READY_FOR_PICKUP'), equals(1));

      // Kasir menyelesaikan pesanan (optimistic update ke COMPLETED, version naik ke 2)
      final updated = controller.updateOrderStatus('ord-101', 'COMPLETED');
      expect(updated, isTrue);

      // Status lokal saat ini adalah COMPLETED (tidak aktif di antrean)
      expect(controller.countForStatus('READY_FOR_PICKUP'), equals(0));
      expect(controller.allOrders.first.orderStatus, equals('COMPLETED'));

      // Jika refresh terjadi dari snapshot yang stale (versi lebih rendah dari COMPLETED lokal),
      // setSnapshot melindungi terminal status lokal agar tidak teregresi ke status lama.
      final staleSnapshot = [
        makeOrder(
          id: 'ord-101',
          orderNumber: '#ORD-101',
          status: 'READY_FOR_PICKUP',
          version: 1,
        ),
      ];

      controller.setSnapshot(staleSnapshot);

      // Verifikasi: Order TIDAK BOLEH muncul kembali sebagai READY_FOR_PICKUP!
      expect(
        controller.countForStatus('READY_FOR_PICKUP'),
        equals(0),
        reason:
            'Pesanan yang telah diselesaikan tidak boleh muncul kembali saat snapshot stale dimuat',
      );
    });

    test(
      'B4.2: SQLite getOrders memfilter pesanan terminal (COMPLETED/CANCELLED/REJECTED)',
      () async {
        final db = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        final repo = QueueLocalRepository(db);

        final activeOrder = makeOrder(
          id: 'ord-act',
          orderNumber: '#ORD-ACT',
          status: 'READY_FOR_PICKUP',
        );
        final completedOrder = makeOrder(
          id: 'ord-cmp',
          orderNumber: '#ORD-CMP',
          status: 'COMPLETED',
        );

        await repo.saveOrders(orders: [activeOrder, completedOrder]);

        final loaded = await repo.getOrders(activeOnly: true);

        // SQLite active queue harus HANYA mengembalikan order aktif, bukan COMPLETED
        expect(
          loaded.any((o) => o.id == 'ord-cmp'),
          isFalse,
          reason:
              'QueueLocalRepository.getOrders tidak boleh menyertakan pesanan COMPLETED',
        );
        expect(loaded.length, equals(1));
        expect(loaded.first.id, equals('ord-act'));

        await db.close();
      },
    );

    test(
      'B4.3: Event WebSocket duplikat untuk pesanan selesai tidak mengubah state terminal',
      () async {
        final initialOrder = makeOrder(
          id: 'ord-404',
          orderNumber: '#ORD-404',
          status: 'COMPLETED',
          version: 5,
        );
        final controller = QueueController(initialOrders: [initialOrder]);

        expect(controller.allOrders.first.orderStatus, equals('COMPLETED'));

        // Event WS duplikat dengan status READY_FOR_PICKUP dan versi lebih rendah
        controller.upsertOrder(
          makeOrder(
            id: 'ord-404',
            orderNumber: '#ORD-404',
            status: 'READY_FOR_PICKUP',
            version: 4,
          ),
          eventId: 'evt-dup-1',
        );

        // Status HARUS TETAP COMPLETED
        expect(controller.allOrders.first.orderStatus, equals('COMPLETED'));

        // Event WS duplikat dengan eventId yang sama
        controller.upsertOrder(
          makeOrder(
            id: 'ord-404',
            orderNumber: '#ORD-404',
            status: 'READY_FOR_PICKUP',
            version: 5,
          ),
          eventId: 'evt-dup-1',
        );

        expect(controller.allOrders.first.orderStatus, equals('COMPLETED'));
      },
    );

    test(
      'B4.4: Selesai via Coordinator mengirim mutasi ke server dan konsisten saat refresh',
      () async {
        final db = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        final repo = QueueLocalRepository(db);
        final outbox = OutboxRepository(db);
        final order = makeOrder(
          id: 'ord-202',
          orderNumber: '#ORD-202',
          status: 'READY_FOR_PICKUP',
          version: 2,
        );
        final gateway = MockTestGateway([order]);
        final controller = QueueController();
        final factory = MockRealtimeFactory();

        final coordinator = QueueRealtimeCoordinator(
          config: ApiConfig(baseUri: Uri.parse('http://localhost:8080/api/v1')),
          accessToken: () async => 'test-token',
          gateway: gateway,
          localQueue: repo,
          outboxRepo: outbox,
          queueController: controller,
          connectionFactory: factory,
        );

        await coordinator.start();
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(1));

        // Selesaikan pesanan via coordinator
        final result = await coordinator.transitionOrderStatus(
          order.id,
          'COMPLETED',
          order.version,
        );
        expect(result.orderStatus, equals('COMPLETED'));
        expect(gateway.lastTransitionedId, equals(order.id));
        expect(gateway.lastTransitionedStatus, equals('COMPLETED'));

        // Di active queue, order sudah tidak ada di tab READY_FOR_PICKUP
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(0));

        // Refresh snapshot dari server
        await coordinator.refreshSnapshot();

        // Order tetap tidak muncul kembali
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(0));

        coordinator.dispose();
        await db.close();
      },
    );

    test(
      'B4.5: Selesai saat offline masuk outbox UPDATE_STATUS dan tetap COMPLETED',
      () async {
        final db = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        final repo = QueueLocalRepository(db);
        final outbox = OutboxRepository(db);
        final order = makeOrder(
          id: 'ord-off-1',
          orderNumber: '#ORD-OFF',
          status: 'READY_FOR_PICKUP',
          version: 1,
        );
        final gateway = MockTestGateway([order]);
        final controller = QueueController();
        final factory = MockRealtimeFactory();
        final connectivity = ConnectivityController(initiallyOnline: false);

        final coordinator = QueueRealtimeCoordinator(
          config: ApiConfig(baseUri: Uri.parse('http://localhost:8080/api/v1')),
          accessToken: () async => 'test-token',
          gateway: gateway,
          localQueue: repo,
          outboxRepo: outbox,
          queueController: controller,
          connectionFactory: factory,
          connectivity: connectivity,
        );

        await coordinator.start();
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(1));

        // Transisi saat offline
        await coordinator.transitionOrderStatus(
          order.id,
          'COMPLETED',
          order.version,
        );

        // Verifikasi di controller lokal sudah COMPLETED
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(0));

        // Verifikasi mutasi tersimpan di outbox
        final pendingMutations = await outbox.getPendingMutations();
        expect(pendingMutations.length, equals(1));
        expect(pendingMutations.first.mutationType, equals('UPDATE_STATUS'));
        expect(pendingMutations.first.payloadJson, contains('COMPLETED'));

        // Verifikasi di SQLite lokal juga sudah ter-update
        final localOrders = await repo.getOrders(activeOnly: false);
        expect(
          localOrders.firstWhere((o) => o.id == order.id).orderStatus,
          equals('COMPLETED'),
        );

        coordinator.dispose();
        await db.close();
      },
    );

    test(
      'B4.6: Rollback transisi jika server menolak penyelesaian pesanan',
      () async {
        final db = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        final repo = QueueLocalRepository(db);
        final order = makeOrder(
          id: 'ord-fail-1',
          orderNumber: '#ORD-FAIL',
          status: 'READY_FOR_PICKUP',
          version: 2,
        );
        final gateway = MockTestGateway([order]);
        gateway.failNextTransition = true; // Server menolak (409 conflict)

        final controller = QueueController();
        final factory = MockRealtimeFactory();

        final coordinator = QueueRealtimeCoordinator(
          config: ApiConfig(baseUri: Uri.parse('http://localhost:8080/api/v1')),
          accessToken: () async => 'test-token',
          gateway: gateway,
          localQueue: repo,
          queueController: controller,
          connectionFactory: factory,
        );

        await coordinator.start();
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(1));

        // Transisi gagal
        await expectLater(
          coordinator.transitionOrderStatus(
            order.id,
            'COMPLETED',
            order.version,
          ),
          throwsA(isA<ApiFailure>()),
        );

        // Verifikasi ROLLBACK: status kembali ke READY_FOR_PICKUP
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(1));
        expect(
          controller.allOrders.first.orderStatus,
          equals('READY_FOR_PICKUP'),
        );

        coordinator.dispose();
        await db.close();
      },
    );

    test(
      'B4.7: Transisi dari PENDING langsung ke PREPARING berhasil',
      () async {
        final db = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        final repo = QueueLocalRepository(db);
        final order = makeOrder(
          id: 'ord-pos-1',
          orderNumber: '#ORD-POS1',
          status: 'PENDING',
          version: 1,
        );
        final gateway = MockTestGateway([order]);
        final controller = QueueController();
        final factory = MockRealtimeFactory();

        final coordinator = QueueRealtimeCoordinator(
          config: ApiConfig(baseUri: Uri.parse('http://localhost:8080/api/v1')),
          accessToken: () async => 'test-token',
          gateway: gateway,
          localQueue: repo,
          queueController: controller,
          connectionFactory: factory,
        );

        await coordinator.start();
        expect(controller.countForStatus('PENDING'), equals(1));

        // Transisi dari PENDING ke PREPARING
        final result = await coordinator.transitionOrderStatus(
          order.id,
          'PREPARING',
          order.version,
        );
        expect(result.orderStatus, equals('PREPARING'));
        expect(controller.countForStatus('PREPARING'), equals(1));
        expect(controller.countForStatus('PENDING'), equals(0));

        coordinator.dispose();
        await db.close();
      },
    );

    test(
      'B4.8: Order UNPAID dibayar lalu diselesaikan tidak stuck dan hilang dari antrean aktif',
      () async {
        final order = makeOrder(
          id: 'ord-unpaid-1',
          orderNumber: '#ORD-UNPAID',
          status: 'READY_FOR_PICKUP',
          paymentStatus: 'UNPAID',
          version: 1,
        );
        final controller = QueueController(initialOrders: [order]);

        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(1));

        // Bayar pesanan
        final paidSuccess = controller.updatePaymentStatus(order.id, 'PAID');
        expect(paidSuccess, isTrue);
        expect(controller.allOrders.first.paymentStatus, equals('PAID'));

        // Selesaikan pesanan setelah dibayar
        final completeSuccess = controller.updateOrderStatus(
          order.id,
          'COMPLETED',
        );
        expect(completeSuccess, isTrue);
        expect(controller.allOrders.first.orderStatus, equals('COMPLETED'));

        // Order TIDAK BOLEH ada di antrean aktif
        expect(
          controller.allOrders
              .where((o) => o.isActive)
              .any((o) => o.id == order.id),
          isFalse,
        );
        expect(controller.countForStatus('READY_FOR_PICKUP'), equals(0));
        expect(controller.countForStatus('ALL'), equals(0));
      },
    );
  });
}
