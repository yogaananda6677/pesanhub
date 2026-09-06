import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts/order_alert_controller.dart';
import '../auth/login_view.dart';
import '../auth/session.dart';
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

/// Creates the authenticated REST/WebSocket graph only when the non-secret
/// backend base URL is configured. Missing configuration cannot bypass login.
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
  ApiConfig? _config;
  SessionController? _session;

  @override
  void initState() {
    super.initState();
    final config = ApiConfig.fromEnvironment();
    if (config == null) return;

    late final SessionController session;
    final api = PesenHubApiClient(
      config: config,
      accessToken: () => session.accessToken(),
    );
    session = SessionController(store: SecureSessionStore(), gateway: api);
    session.addListener(_onSessionChanged);
    _config = config;
    _api = api;
    _session = session;
    unawaited(session.restore());
  }

  void _onSessionChanged() {
    final session = _session;
    if (!mounted || session == null) return;
    if (session.status == SessionStatus.signedIn && _coordinator == null) {
      _startServices();
    } else if (session.status == SessionStatus.signedOut &&
        _coordinator != null) {
      _stopServices();
    }
    setState(() {});
  }

  void _startServices() {
    final config = _config;
    final api = _api;
    final session = _session;
    if (config == null || api == null || session == null) return;

    final database = LocalDatabase();
    final queueRepository = QueueLocalRepository(database);
    final outboxRepository = OutboxRepository(database);
    final alerts = OrderAlertController();
    final queueController = QueueController(alertController: alerts);
    final cartController = CartController();
    final sync = SyncService(
      outboxRepo: outboxRepository,
      queueRepo: queueRepository,
      gateway: api,
    );
    final coordinator = QueueRealtimeCoordinator(
      config: config,
      accessToken: session.accessToken,
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
    _sync = sync;
    _queueRepository = queueRepository;
    _outboxRepository = outboxRepository;
    _queueController = queueController;
    _cartController = cartController;
    _coordinator = coordinator;
    _alerts = alerts;
    unawaited(coordinator.start());
  }

  void _stopServices() {
    _coordinator?.dispose();
    _sync?.dispose();
    _queueController?.dispose();
    _cartController?.dispose();
    _alerts?.dispose();
    unawaited(_database?.close());
    _database = null;
    _sync = null;
    _queueRepository = null;
    _outboxRepository = null;
    _queueController = null;
    _cartController = null;
    _coordinator = null;
    _alerts = null;
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    _stopServices();
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (_config == null) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Backend belum dikonfigurasi. Atur PESENHUB_API_BASE_URL untuk menjalankan aplikasi.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (session != null) {
      if (session.status == SessionStatus.restoring) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (session.status != SessionStatus.signedIn) {
        return LoginView(controller: session);
      }
    }
    return AppShell(
      queueController: _queueController,
      cartController: _cartController,
      submitOrder: _api == null ? null : _submitOrder,
      alertController: _alerts,
      onSignOut: session?.signOut,
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
