import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum OperationalConnectionState { online, offline, syncing }

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
  OperationalConnectionState _state;
  StreamSubscription<bool>? _subscription;
  bool _networkOnline;

  ConnectivityController({
    ConnectivityMonitor? monitor,
    bool initiallyOnline = true,
  }) : monitor = monitor ?? PlatformConnectivityMonitor(),
       _networkOnline = initiallyOnline,
       _state = initiallyOnline
           ? OperationalConnectionState.online
           : OperationalConnectionState.offline;

  OperationalConnectionState get state => _state;

  Future<void> start() async {
    try {
      _setOnline(await monitor.isOnline());
    } catch (_) {
      _setOnline(false);
    }
    await _subscription?.cancel();
    _subscription = monitor.changes.listen(
      _setOnline,
      onError: (_) => _setOnline(false),
    );
  }

  void setSyncing(bool syncing) {
    final next = syncing
        ? OperationalConnectionState.syncing
        : (_networkOnline
              ? OperationalConnectionState.online
              : OperationalConnectionState.offline);
    _setState(next);
  }

  void _setOnline(bool online) {
    _networkOnline = online;
    if (_state != OperationalConnectionState.syncing) {
      _setState(
        online
            ? OperationalConnectionState.online
            : OperationalConnectionState.offline,
      );
    }
  }

  void _setState(OperationalConnectionState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
