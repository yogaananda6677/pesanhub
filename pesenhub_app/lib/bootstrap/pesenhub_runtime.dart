import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts/order_alert_controller.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/models/cart_order_draft.dart';
import '../data/local/local_database.dart';
import '../data/local/outbox_repository.dart';
import '../data/local/queue_local_repository.dart';
import '../data/remote/api_config.dart';
import '../data/remote/pesenhub_api_client.dart';
import '../data/remote/queue_realtime_coordinator.dart';
import '../data/sync/sync_service.dart';
import '../queue/controllers/queue_controller.dart';
import '../queue/models/queue_order.dart';
import '../shell/app_shell.dart';

/// Creates the production REST/WebSocket graph only when safe build-time
/// configuration is present. Local showcase builds keep their sample data.
class PesenHubRuntime extends StatefulWidget {
  const PesenHubRuntime({super.key});

  @override
  State<PesenHubRuntime> createState() => _PesenHubRuntimeState();
}

class _PesenHubRuntimeState extends State<PesenHubRuntime> {
  LocalDatabase? _database;
  PesenHubApiClient? _api;
  SyncService? _sync;
  QueueLocalRepository? _queueRepository;
  OutboxRepository? _outboxRepository;
  QueueController? _queueController;
  CartController? _cartController;
  QueueRealtimeCoordinator? _coordinator;
  OrderAlertController? _alerts;

  @override
  void initState() {
    super.initState();
    final config = ApiConfig.fromEnvironment();
    if (config == null) return;

    final database = LocalDatabase();
    final queueRepository = QueueLocalRepository(database);
    final outboxRepository = OutboxRepository(database);
    final alerts = OrderAlertController();
    final queueController = QueueController(alertController: alerts);
    final cartController = CartController();
    final api = PesenHubApiClient(config: config);
    final sync = SyncService(
      outboxRepo: outboxRepository,
      queueRepo: queueRepository,
      gateway: api,
    );
    final coordinator = QueueRealtimeCoordinator(
      config: config,
      gateway: api,
      localQueue: queueRepository,
      queueController: queueController,
      flushOutbox: () async {
        await sync.refreshState();
        if (sync.state.pendingCount == 0) return false;
        final result = await sync.syncPendingMutations();
        return result.syncedCount > 0;
      },
    );

    _database = database;
    _api = api;
    _sync = sync;
    _queueRepository = queueRepository;
    _outboxRepository = outboxRepository;
    _queueController = queueController;
    _cartController = cartController;
    _coordinator = coordinator;
    _alerts = alerts;
    unawaited(coordinator.start());
  }

  @override
  void dispose() {
    _coordinator?.dispose();
    _sync?.dispose();
    _queueController?.dispose();
    _cartController?.dispose();
    _api?.close();
    _alerts?.dispose();
    unawaited(_database?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      queueController: _queueController,
      cartController: _cartController,
      submitOrder: _api == null ? null : _submitOrder,
      alertController: _alerts,
    );
  }

  Future<QueueOrder> _submitOrder(CartOrderDraft draft) async {
    final database = _database;
    final cart = _cartController;
    final queue = _queueController;
    final sync = _sync;
    final api = _api;
    final queueRepository = _queueRepository;
    final outboxRepository = _outboxRepository;
    if (database == null ||
        cart == null ||
        queue == null ||
        sync == null ||
        api == null ||
        queueRepository == null ||
        outboxRepository == null) {
      throw StateError('Backend runtime is not configured');
    }

    final order = await cart.persistOfflineDraft(
      draft: draft,
      outboxRepo: outboxRepository,
      queueRepo: queueRepository,
    );
    queue.upsertOrder(order);
    final result = await sync.syncPendingMutations();
    if (result.syncedCount > 0) {
      try {
        final snapshot = await api.fetchQueue();
        queue.setSnapshot(snapshot);
        await queueRepository.saveOrders(orders: snapshot);
      } catch (_) {
        // The acknowledged outbox remains SYNCED. WebSocket or the next
        // reconnect snapshot will replace the optimistic local order.
      }
    }
    return order;
  }
}
