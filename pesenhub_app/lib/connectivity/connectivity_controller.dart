import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum OperationalConnectionState {
  online,
  offline,
  syncing,
  degraded,
  sessionExpired,
}

enum BackendFailureKind { unreachable, degraded, sessionExpired }

abstract class ConnectivityMonitor {
  Future<bool> isOnline();
  Stream<bool> get changes;
}

class PlatformConnectivityMonitor implements ConnectivityMonitor {
  final Connectivity _connectivity;
  PlatformConnectivityMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  @override
  Future<bool> isOnline() async =>
      _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_online).distinct();

  static bool _online(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.contains(ConnectivityResult.none);
}

class ConnectivityController extends ChangeNotifier {
  final ConnectivityMonitor monitor;
  final bool backendAware;
  final ValueChanged<bool>? onNetworkChanged;
  final VoidCallback? onRetryRequested;
  final void Function(
    OperationalConnectionState from,
    OperationalConnectionState to,
  )?
  onTransition;
  OperationalConnectionState _state;
  StreamSubscription<bool>? _subscription;
  bool _networkOnline;
  bool _syncing = false;
  bool? _backendReachable;
  BackendFailureKind? _backendFailure;

  int pendingCount = 0;
  int permanentFailureCount = 0;
  int retryAttempt = 0;
  DateTime? lastSuccessfulSyncAt;
  DateTime? lastBackendResponseAt;
  DateTime? nextRetryAt;
  String? lastRequestId;

  ConnectivityController({
    ConnectivityMonitor? monitor,
    bool initiallyOnline = true,
    this.backendAware = false,
    this.onNetworkChanged,
    this.onRetryRequested,
    this.onTransition,
  }) : monitor = monitor ?? PlatformConnectivityMonitor(),
       _networkOnline = initiallyOnline,
       _state = initiallyOnline
           ? (backendAware
                 ? OperationalConnectionState.degraded
                 : OperationalConnectionState.online)
           : OperationalConnectionState.offline;

  OperationalConnectionState get state => _state;
  bool get networkOnline => _networkOnline;
  bool get backendReachable => _backendReachable == true;

  Future<void> start() async {
    try {
      _setNetworkOnline(await monitor.isOnline(), forceCallback: true);
    } catch (_) {
      _setNetworkOnline(false, forceCallback: true);
    }
    await _subscription?.cancel();
    _subscription = monitor.changes.listen(
      _setNetworkOnline,
      onError: (_) => _setNetworkOnline(false),
    );
  }

  void reportBackendReachable({DateTime? at}) {
    _backendReachable = true;
    _backendFailure = null;
    final timestamp = (at ?? DateTime.now()).toUtc();
    lastBackendResponseAt = timestamp;
    lastSuccessfulSyncAt = timestamp;
    retryAttempt = 0;
    nextRetryAt = null;
    lastRequestId = null;
    _recompute();
  }

  void reportBackendFailure(
    BackendFailureKind kind, {
    String? requestId,
    int? attempt,
    DateTime? retryAt,
  }) {
    _backendReachable = false;
    _backendFailure = kind;
    lastRequestId = requestId;
    retryAttempt = attempt ?? retryAttempt;
    nextRetryAt = retryAt;
    _recompute();
  }

  void updateSyncState({
    required bool isSyncing,
    required int pending,
    required int permanentFailures,
    DateTime? lastSyncedAt,
    DateTime? retryAt,
  }) {
    _syncing = isSyncing;
    pendingCount = pending;
    permanentFailureCount = permanentFailures;
    if (lastSyncedAt != null) {
      lastSuccessfulSyncAt = lastSyncedAt.toUtc();
    }
    nextRetryAt = retryAt?.toUtc();
    _recompute(forceNotify: true);
  }

  void setSyncing(bool syncing) {
    _syncing = syncing;
    _recompute();
  }

  void requestRetry() => onRetryRequested?.call();

  void _setNetworkOnline(bool online, {bool forceCallback = false}) {
    final changed = _networkOnline != online;
    _networkOnline = online;
    if (!online) {
      _backendReachable = false;
      _backendFailure = BackendFailureKind.unreachable;
    } else if (changed && backendAware) {
      _backendReachable = null;
      _backendFailure = null;
    }
    _recompute();
    if (changed || forceCallback) onNetworkChanged?.call(online);
  }

  void _recompute({bool forceNotify = false}) {
    OperationalConnectionState next;
    if (!_networkOnline) {
      next = OperationalConnectionState.offline;
    } else if (backendAware &&
        _backendFailure == BackendFailureKind.sessionExpired) {
      next = OperationalConnectionState.sessionExpired;
    } else if (_syncing) {
      next = OperationalConnectionState.syncing;
    } else if (!backendAware) {
      next = OperationalConnectionState.online;
    } else if (_backendReachable == true) {
      next = OperationalConnectionState.online;
    } else if (_backendFailure == BackendFailureKind.unreachable) {
      next = OperationalConnectionState.offline;
    } else {
      next = OperationalConnectionState.degraded;
    }
    if (_state == next && !forceNotify) return;
    final previous = _state;
    _state = next;
    notifyListeners();
    if (previous != next) onTransition?.call(previous, next);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
