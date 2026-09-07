import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts/order_alert_controller.dart';
import '../auth/login_view.dart';
import '../auth/approval_locked_view.dart';
import '../auth/google_identity_client.dart';
import '../auth/session.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/models/cart_order_draft.dart';
import '../connectivity/connectivity_controller.dart';
import '../data/local/local_database.dart';
import '../data/local/menu_local_repository.dart';
import '../data/local/outbox_repository.dart';
import '../data/local/queue_local_repository.dart';
import '../data/remote/api_config.dart';
import '../data/remote/catalog_runtime_coordinator.dart';
import '../data/remote/pesenhub_api_client.dart';
import '../data/remote/queue_realtime_coordinator.dart';
import '../data/sync/sync_service.dart';
import '../menu/controllers/menu_availability_controller.dart';
import '../menu/controllers/menu_controller.dart' as mc;
import '../menu/models/menu_category.dart';
import '../menu/models/menu_item.dart';
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
  ConnectivityController? _connectivity;
  VoidCallback? _syncListener;
  mc.MenuController? _menuController;
  MenuAvailabilityController? _menuManagementController;
  CatalogRuntimeCoordinator? _catalogCoordinator;
  VoidCallback? _catalogConnectivityListener;

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
    session = SessionController(
      store: SecureSessionStore(),
      gateway: api,
      identityClient: PlatformGoogleIdentityClient(
        serverClientId: config.googleServerClientId,
      ),
    );
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
    } else if (session.status != SessionStatus.signedIn &&
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
    final menuRepository = MenuLocalRepository(database);
    final outboxRepository = OutboxRepository(database);
    final alerts = OrderAlertController();
    final queueController = QueueController(alertController: alerts);
    final cartController = CartController();
    late final QueueRealtimeCoordinator coordinator;
    late final CatalogRuntimeCoordinator catalogCoordinator;
    final sync = SyncService(
      outboxRepo: outboxRepository,
      queueRepo: queueRepository,
      gateway: api,
      onRetryDue: () => coordinator.retryNow(),
    );
    final connectivity = ConnectivityController(
      initiallyOnline: false,
      backendAware: true,
      onNetworkChanged: (available) =>
          coordinator.setNetworkAvailable(available),
      onRetryRequested: () => coordinator.retryNow(),
      onTransition: (from, to) {
        debugPrint('PesenHub connectivity ${from.name} -> ${to.name}');
        if (to == OperationalConnectionState.online) {
          unawaited(catalogCoordinator.refresh());
        }
      },
    );
    final menuController = mc.MenuController();
    late final MenuAvailabilityController menuManagementController;
    Future<void> persistCatalog(
      List<MenuCategory> categories,
      List<MenuItem> menus,
    ) async {
      try {
        await menuRepository.saveCatalog(categories: categories, items: menus);
      } catch (_) {
        if (_menuManagementController == menuManagementController) {
          menuManagementController.setBanner(
            'Perubahan tersimpan di Backend, tetapi cache offline belum dapat diperbarui.',
            isError: true,
          );
        }
      }
    }

    void publishCatalog(List<MenuCategory> categories, List<MenuItem> menus) {
      menuController.setCatalog(categories, menus);
      unawaited(persistCatalog(categories, menus));
    }

    menuManagementController = MenuAvailabilityController(
      availabilityUpdateFn: api.updateMenuAvailability,
      createCategoryFn: api.createCategory,
      updateCategoryFn: api.updateCategory,
      createMenuFn: api.createMenu,
      updateMenuFn: api.updateMenu,
      canMutate: () => connectivity.backendReachable,
      onRefresh: () => catalogCoordinator.refresh(),
      onAvailabilityChanged: menuController.upsertMenu,
      onCatalogChanged: publishCatalog,
    );
    catalogCoordinator = CatalogRuntimeCoordinator(
      gateway: api,
      localRepository: menuRepository,
      menuController: menuController,
      managementController: menuManagementController,
    );
    void catalogConnectivityListener() =>
        menuManagementController.connectivityChanged();
    connectivity.addListener(catalogConnectivityListener);
    coordinator = QueueRealtimeCoordinator(
      config: config,
      accessToken: session.accessToken,
      gateway: api,
      localQueue: queueRepository,
      queueController: queueController,
      connectivity: connectivity,
      onSessionExpired: session.signOut,
      flushOutbox: () async {
        await sync.refreshState();
        if (sync.state.pendingCount == 0) return false;
        final result = await sync.syncPendingMutations();
        return result.syncedCount > 0;
      },
    );
    void syncListener() {
      final state = sync.state;
      connectivity.updateSyncState(
        isSyncing: state.isSyncing,
        pending: state.pendingCount,
        permanentFailures: state.permanentFailureCount,
        lastSyncedAt: state.lastSyncedAt,
        retryAt: state.nextRetryAt,
      );
    }

    sync.addListener(syncListener);

    _database = database;
    _sync = sync;
    _queueRepository = queueRepository;
    _outboxRepository = outboxRepository;
    _queueController = queueController;
    _cartController = cartController;
    _coordinator = coordinator;
    _alerts = alerts;
    _connectivity = connectivity;
    _syncListener = syncListener;
    _menuController = menuController;
    _menuManagementController = menuManagementController;
    _catalogCoordinator = catalogCoordinator;
    _catalogConnectivityListener = catalogConnectivityListener;
    unawaited(coordinator.start());
    unawaited(catalogCoordinator.start());
  }

  void _stopServices() {
    final sync = _sync;
    final syncListener = _syncListener;
    if (sync != null && syncListener != null) {
      sync.removeListener(syncListener);
    }
    final connectivity = _connectivity;
    final catalogConnectivityListener = _catalogConnectivityListener;
    if (connectivity != null && catalogConnectivityListener != null) {
      connectivity.removeListener(catalogConnectivityListener);
    }
    _coordinator?.dispose();
    _sync?.dispose();
    _queueController?.dispose();
    _cartController?.dispose();
    _alerts?.dispose();
    _connectivity?.dispose();
    _catalogCoordinator?.dispose();
    _menuManagementController?.dispose();
    _menuController?.dispose();
    unawaited(_database?.close());
    _database = null;
    _sync = null;
    _queueRepository = null;
    _outboxRepository = null;
    _queueController = null;
    _cartController = null;
    _coordinator = null;
    _alerts = null;
    _connectivity = null;
    _syncListener = null;
    _menuController = null;
    _menuManagementController = null;
    _catalogCoordinator = null;
    _catalogConnectivityListener = null;
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
      if (session.status == SessionStatus.signedOut ||
          session.status == SessionStatus.signingIn) {
        return LoginView(controller: session);
      }
      if (session.status != SessionStatus.signedIn) {
        return ApprovalLockedView(controller: session);
      }
    }
    return AppShell(
      queueController: _queueController,
      cartController: _cartController,
      submitOrder: _api == null ? null : _submitOrder,
      alertController: _alerts,
      connectivityController: _connectivity,
      onSignOut: session?.signOut,
      menuController: _menuController,
      menuManagementController: _menuManagementController,
    );
  }

  Future<QueueOrder> _submitOrder(CartOrderDraft draft) async {
    final cart = _cartController;
    final queue = _queueController;
    final sync = _sync;
    final queueRepository = _queueRepository;
    final outboxRepository = _outboxRepository;
    if (cart == null ||
        queue == null ||
        sync == null ||
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
    await sync.refreshState();
    _coordinator?.retryNow();
    return order;
  }
}
