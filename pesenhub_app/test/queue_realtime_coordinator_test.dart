import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/data/local/models/outbox_mutation.dart';
import 'package:pesenhub_app/data/local/outbox_repository.dart';
import 'package:pesenhub_app/data/local/queue_local_repository.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/data/remote/queue_realtime_coordinator.dart';
import 'package:pesenhub_app/data/remote/realtime_connection.dart';
import 'package:pesenhub_app/queue/controllers/queue_controller.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

QueueOrder _order(int version, String status) => QueueOrder(
  id: 'order-1',
  orderNumber: 'ORD-001',
  customerName: 'Pelanggan Uji',
  customerPhone: '0812****7890',
  source: 'CASHIER_MANUAL',
  orderStatus: status,
  paymentStatus: 'UNPAID',
  createdAt: DateTime.utc(2026, 9, 5, 8),
  version: version,
  items: const [
    QueueOrderItem(name: 'Nasi Goreng', quantity: 1, unitPrice: 20000),
  ],
);

class _Gateway implements QueueRemoteGateway {
  final List<List<QueueOrder>> snapshots;
  int snapshotCalls = 0;

  _Gateway(this.snapshots);

  @override
  Future<List<QueueOrder>> fetchQueue() async {
    final index = snapshotCalls.clamp(0, snapshots.length - 1);
    snapshotCalls++;
    return snapshots[index];
  }

  @override
  Future<QueueOrder> fetchOrder(String id) async => snapshots.last.single;
}

class _Connection implements RealtimeConnection {
  final controller = StreamController<dynamic>();

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get messages => controller.stream;

  @override
  Future<void> close() async {}
}

class _ConnectionFactory implements RealtimeConnectionFactory {
  final connections = <_Connection>[];

  @override
  RealtimeConnection connect(Uri uri) {
    final connection = _Connection();
    connections.add(connection);
    return connection;
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 25));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'snapshot, newer events, duplicate guard, gap recovery, and reconnect',
    () async {
      final database = LocalDatabase(
        customPath: inMemoryDatabasePath,
        customFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final localQueue = QueueLocalRepository(database);
      final outbox = OutboxRepository(database);
      await outbox.enqueueMutation(
        OutboxMutation(
          id: 'mutation-1',
          idempotencyKey: 'idem-1',
          clientOrderId: 'client-1',
          payloadJson: '{}',
          createdAt: DateTime.utc(2026, 9, 5),
        ),
      );
      final gateway = _Gateway([
        [_order(1, 'PENDING')],
        [_order(4, 'READY_FOR_PICKUP')],
        [_order(5, 'COMPLETED')],
      ]);
      final queue = QueueController();
      final connections = _ConnectionFactory();
      final coordinator = QueueRealtimeCoordinator(
        config: ApiConfig(
          baseUri: Uri.parse('https://api.example.test/api/v1/'),
          token: 'mobile-test-token-at-least-32-characters',
        ),
        gateway: gateway,
        localQueue: localQueue,
        queueController: queue,
        connectionFactory: connections,
        baseReconnectDelay: const Duration(milliseconds: 1),
        maxReconnectDelay: const Duration(milliseconds: 2),
      );
      addTearDown(coordinator.stop);

      await coordinator.start();
      expect(queue.totalCount, 1);
      expect(queue.allOrders.single.version, 1);

      connections.connections.single.controller.add(
        jsonEncode({
          'event_id': 'event-2',
          'event_type': 'ORDER_STATUS_CHANGED',
          'order_id': 'order-1',
          'status': 'PREPARING',
          'version': 2,
        }),
      );
      await _settle();
      expect(queue.allOrders.single.version, 2);
      expect(queue.allOrders.single.orderStatus, 'PREPARING');

      connections.connections.single.controller.add(
        jsonEncode({
          'event_id': 'event-2',
          'event_type': 'ORDER_STATUS_CHANGED',
          'order_id': 'order-1',
          'status': 'PREPARING',
          'version': 2,
        }),
      );
      await _settle();
      expect(queue.totalCount, 1);

      connections.connections.single.controller.add(
        jsonEncode({
          'event_id': 'event-4',
          'event_type': 'ORDER_STATUS_CHANGED',
          'order_id': 'order-1',
          'status': 'READY_FOR_PICKUP',
          'version': 4,
        }),
      );
      await _settle();
      expect(queue.allOrders.single.version, 4);
      expect(gateway.snapshotCalls, 2);

      await connections.connections.single.controller.close();
      await _settle();
      expect(connections.connections.length, greaterThanOrEqualTo(2));
      expect(queue.allOrders.single.version, 5);
      expect(await outbox.getAllMutations(), hasLength(1));
    },
  );
}
