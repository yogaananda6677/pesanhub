import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../connectivity/connectivity_controller.dart';
import '../../queue/controllers/queue_controller.dart';
import '../../queue/models/queue_order.dart';
import '../local/queue_local_repository.dart';
import 'api_config.dart';
import 'api_failure.dart';
import 'order_dto.dart';
import 'pesenhub_api_client.dart';
import 'realtime_connection.dart';

enum RealtimeConnectionState {
  idle,
  recovering,
  connecting,
  connected,
  backingOff,
  stopped,
}

class QueueRealtimeState {
  final RealtimeConnectionState connection;
  final ApiFailureKind? failureKind;
  final String? requestId;
  final int reconnectAttempt;
  final DateTime? lastRecoveredAt;
  final DateTime? lastEventAt;

  const QueueRealtimeState({
    this.connection = RealtimeConnectionState.idle,
    this.failureKind,
    this.requestId,
    this.reconnectAttempt = 0,
    this.lastRecoveredAt,
    this.lastEventAt,
  });

  QueueRealtimeState copyWith({
    RealtimeConnectionState? connection,
    ApiFailureKind? failureKind,
    bool clearFailure = false,
    String? requestId,
    int? reconnectAttempt,
    DateTime? lastRecoveredAt,
    DateTime? lastEventAt,
  }) {
    return QueueRealtimeState(
      connection: connection ?? this.connection,
      failureKind: clearFailure ? null : failureKind ?? this.failureKind,
      requestId: clearFailure ? null : requestId ?? this.requestId,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      lastRecoveredAt: lastRecoveredAt ?? this.lastRecoveredAt,
      lastEventAt: lastEventAt ?? this.lastEventAt,
    );
  }
}

class QueueRealtimeCoordinator extends ChangeNotifier {
  final ApiConfig config;
  final Future<String?> Function() accessToken;
  final QueueRemoteGateway gateway;
  final QueueLocalRepository localQueue;
  final QueueController queueController;
  final RealtimeConnectionFactory connectionFactory;
  final Future<bool> Function()? flushOutbox;
  final Duration baseReconnectDelay;
  final Duration maxReconnectDelay;
  final ConnectivityController? connectivity;
  final Future<void> Function()? onSessionExpired;
  final double Function() randomDouble;

  QueueRealtimeState _state = const QueueRealtimeState();
  QueueRealtimeState get state => _state;

  RealtimeConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _recovering = false;
  bool _closingConnection = false;
  bool _networkAvailable = true;
  bool _disposed = false;

  QueueRealtimeCoordinator({
    required this.config,
    required this.accessToken,
    required this.gateway,
    required this.localQueue,
    required this.queueController,
    this.connectionFactory = const WebSocketRealtimeConnectionFactory(),
    this.flushOutbox,
    this.baseReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.connectivity,
    this.onSessionExpired,
    double Function()? randomDouble,
  }) : randomDouble = randomDouble ?? Random().nextDouble;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final cached = await localQueue.getOrdersWithFreshness();
    if (cached.data.isNotEmpty) {
      queueController.setSnapshot(
        cached.data,
        isStale: cached.isStale,
        isOffline: true,
      );
    }
    await _recoverAndConnect();
  }

  Future<void> _recoverAndConnect() async {
    if (!_canRecover || _recovering) return;
    var expireSession = false;
    _recovering = true;
    connectivity?.setSyncing(true);
    _setState(_state.copyWith(connection: RealtimeConnectionState.recovering));
    try {
      await flushOutbox?.call();
      if (!_canRecover) return;
      await _recoverSnapshot();
      if (!_canRecover) return;
      await _connect();
      if (_canRecover) connectivity?.reportBackendReachable();
    } on ApiFailure catch (failure) {
      _reportFailure(failure);
      _setState(
        _state.copyWith(
          failureKind: failure.kind,
          requestId: failure.requestId,
        ),
      );
      if (failure.isTransient) {
        _scheduleReconnect();
      } else {
        _started = false;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        if (failure.kind == ApiFailureKind.unauthenticated) {
          expireSession = true;
        }
        _setState(_state.copyWith(connection: RealtimeConnectionState.stopped));
        await _closeConnection();
      }
    } catch (_) {
      const failure = ApiFailure(ApiFailureKind.network);
      _reportFailure(failure);
      _setState(_state.copyWith(failureKind: failure.kind));
      _scheduleReconnect();
    } finally {
      _recovering = false;
      if (!_disposed) connectivity?.setSyncing(false);
    }
    if (expireSession) await onSessionExpired?.call();
  }

  bool get _canRecover => _started && !_disposed && _networkAvailable;

  Future<void> _recoverSnapshot() async {
    final orders = await gateway.fetchQueue();
    if (!_canRecover) return;
    await localQueue.saveOrders(orders: orders, preserveUnsyncedLocal: true);
    if (!_canRecover) return;
    final mergedOrders = await localQueue.getOrders();
    if (!_canRecover) return;
    queueController.setSnapshot(mergedOrders);
    _setState(
      _state.copyWith(
        clearFailure: true,
        lastRecoveredAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _connect() async {
    if (!_canRecover) return;
    await _closeConnection();
    if (!_canRecover) return;
    _setState(_state.copyWith(connection: RealtimeConnectionState.connecting));
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const ApiFailure(ApiFailureKind.unauthenticated);
    }
    final connection = connectionFactory.connect(config.websocketUri(token));
    _connection = connection;
    await connection.ready.timeout(config.requestTimeout);
    if (!_canRecover || !identical(connection, _connection)) {
      await connection.close();
      return;
    }
    _subscription = connection.messages.listen(
      (message) => unawaited(_handleMessage(message)),
      onError: (_) => _handleDisconnect(),
      onDone: _handleDisconnect,
      cancelOnError: true,
    );
    _setState(
      _state.copyWith(
        connection: RealtimeConnectionState.connected,
        reconnectAttempt: 0,
        clearFailure: true,
      ),
    );
  }

  Future<void> _handleMessage(dynamic message) async {
    if (!_started || message is! String) return;
    try {
      final raw = jsonDecode(message);
      if (raw is! Map) throw const FormatException('invalid event');
      final event = OrderEventDto.fromJson(Map<String, dynamic>.from(raw));
      final existing = _findOrder(event.orderId);
      if (existing != null && event.version <= existing.version) return;

      if (existing == null) {
        final order = await gateway.fetchOrder(event.orderId);
        queueController.upsertOrder(order, eventId: event.eventId);
        await localQueue.saveOrders(orders: queueController.allOrders);
      } else if (event.version == existing.version + 1) {
        queueController.upsertOrder(
          existing.copyWith(orderStatus: event.status, version: event.version),
          eventId: event.eventId,
        );
        await localQueue.saveOrders(orders: queueController.allOrders);
      } else {
        await _recoverSnapshot();
      }
      _setState(
        _state.copyWith(
          lastEventAt: DateTime.now().toUtc(),
          clearFailure: true,
        ),
      );
      connectivity?.reportBackendReachable();
    } on ApiFailure catch (failure) {
      _reportFailure(failure);
      _setState(
        _state.copyWith(
          failureKind: failure.kind,
          requestId: failure.requestId,
        ),
      );
      if (failure.isTransient) {
        _scheduleReconnect();
      } else {
        _started = false;
        _reconnectTimer?.cancel();
        _setState(_state.copyWith(connection: RealtimeConnectionState.stopped));
        await _closeConnection();
        if (failure.kind == ApiFailureKind.unauthenticated) {
          await onSessionExpired?.call();
        }
      }
    } catch (_) {
      const failure = ApiFailure(ApiFailureKind.invalidResponse);
      _reportFailure(failure);
      _started = false;
      _setState(_state.copyWith(failureKind: ApiFailureKind.invalidResponse));
      _setState(_state.copyWith(connection: RealtimeConnectionState.stopped));
      await _closeConnection();
    }
  }

  QueueOrder? _findOrder(String id) {
    for (final order in queueController.allOrders) {
      if (order.id == id) return order;
    }
    return null;
  }

  void _handleDisconnect() {
    if (!_started || _closingConnection) return;
    _reportFailure(const ApiFailure(ApiFailureKind.network));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_started || !_networkAvailable || _reconnectTimer?.isActive == true) {
      return;
    }
    final attempt = _state.reconnectAttempt + 1;
    final multiplier = pow(2, min(attempt - 1, 6)).toInt();
    final baseDelayMs = min(
      baseReconnectDelay.inMilliseconds * multiplier,
      maxReconnectDelay.inMilliseconds,
    );
    final jitter = 0.8 + (randomDouble().clamp(0.0, 1.0) * 0.4);
    final delayMs = min(
      (baseDelayMs * jitter).round(),
      maxReconnectDelay.inMilliseconds,
    );
    final retryAt = DateTime.now().toUtc().add(Duration(milliseconds: delayMs));
    connectivity?.reportBackendFailure(
      BackendFailureKind.unreachable,
      requestId: _state.requestId,
      attempt: attempt,
      retryAt: retryAt,
    );
    _setState(
      _state.copyWith(
        connection: RealtimeConnectionState.backingOff,
        reconnectAttempt: attempt,
      ),
    );
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      unawaited(_recoverAndConnect());
    });
  }

  void _reportFailure(ApiFailure failure) {
    if (_disposed) return;
    if (failure.isTransient) {
      queueController.markOffline();
      connectivity?.reportBackendFailure(
        BackendFailureKind.unreachable,
        requestId: failure.requestId,
      );
      return;
    }
    queueController.setError(failure.presentationMessage);
    connectivity?.reportBackendFailure(
      failure.kind == ApiFailureKind.unauthenticated
          ? BackendFailureKind.sessionExpired
          : BackendFailureKind.degraded,
      requestId: failure.requestId,
    );
  }

  void setNetworkAvailable(bool available) {
    if (_disposed) return;
    _networkAvailable = available;
    if (!available) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reportFailure(const ApiFailure(ApiFailureKind.network));
      unawaited(_closeConnection());
      return;
    }
    retryNow();
  }

  void retryNow() {
    if (!_canRecover) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_recoverAndConnect());
  }

  void _setState(QueueRealtimeState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  Future<void> _closeConnection() async {
    _closingConnection = true;
    try {
      await _subscription?.cancel();
      _subscription = null;
      final connection = _connection;
      _connection = null;
      if (connection != null) await connection.close();
    } finally {
      _closingConnection = false;
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeConnection();
    _setState(_state.copyWith(connection: RealtimeConnectionState.stopped));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    _reconnectTimer?.cancel();
    unawaited(_closeConnection());
    super.dispose();
  }
}
