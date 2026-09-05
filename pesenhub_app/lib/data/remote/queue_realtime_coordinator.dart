import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

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
  final QueueRemoteGateway gateway;
  final QueueLocalRepository localQueue;
  final QueueController queueController;
  final RealtimeConnectionFactory connectionFactory;
  final Future<bool> Function()? flushOutbox;
  final Duration baseReconnectDelay;
  final Duration maxReconnectDelay;

  QueueRealtimeState _state = const QueueRealtimeState();
  QueueRealtimeState get state => _state;

  RealtimeConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _recovering = false;
  bool _closingConnection = false;

  QueueRealtimeCoordinator({
    required this.config,
    required this.gateway,
    required this.localQueue,
    required this.queueController,
    this.connectionFactory = const WebSocketRealtimeConnectionFactory(),
    this.flushOutbox,
    this.baseReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
  });

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
    if (!_started || _recovering) return;
    _recovering = true;
    _setState(_state.copyWith(connection: RealtimeConnectionState.recovering));
    try {
      await _recoverSnapshot();
      final changed = await flushOutbox?.call() ?? false;
      if (changed) await _recoverSnapshot();
      await _connect();
    } on ApiFailure catch (failure) {
      queueController.setError(failure.presentationMessage);
      _setState(
        _state.copyWith(
          failureKind: failure.kind,
          requestId: failure.requestId,
        ),
      );
      if (failure.isTransient) {
        _scheduleReconnect();
      } else {
        _setState(_state.copyWith(connection: RealtimeConnectionState.stopped));
      }
    } catch (_) {
      const failure = ApiFailure(ApiFailureKind.network);
      queueController.setError(failure.presentationMessage);
      _setState(_state.copyWith(failureKind: failure.kind));
      _scheduleReconnect();
    } finally {
      _recovering = false;
    }
  }

  Future<void> _recoverSnapshot() async {
    final orders = await gateway.fetchQueue();
    queueController.setSnapshot(orders);
    await localQueue.saveOrders(orders: orders);
    _setState(
      _state.copyWith(
        clearFailure: true,
        lastRecoveredAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _connect() async {
    await _closeConnection();
    _setState(_state.copyWith(connection: RealtimeConnectionState.connecting));
    final connection = connectionFactory.connect(config.websocketUri());
    _connection = connection;
    await connection.ready.timeout(config.requestTimeout);
    if (!_started || !identical(connection, _connection)) {
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
    } on ApiFailure catch (failure) {
      queueController.setError(failure.presentationMessage);
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
      }
    } catch (_) {
      queueController.setError(
        const ApiFailure(ApiFailureKind.invalidResponse).presentationMessage,
      );
      _setState(_state.copyWith(failureKind: ApiFailureKind.invalidResponse));
      _scheduleReconnect();
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
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_started || _reconnectTimer?.isActive == true) return;
    final attempt = _state.reconnectAttempt + 1;
    final multiplier = pow(2, min(attempt - 1, 6)).toInt();
    final delayMs = min(
      baseReconnectDelay.inMilliseconds * multiplier,
      maxReconnectDelay.inMilliseconds,
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

  void _setState(QueueRealtimeState value) {
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
    if (!_started) return;
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeConnection();
    _setState(_state.copyWith(connection: RealtimeConnectionState.stopped));
  }

  @override
  void dispose() {
    _started = false;
    _reconnectTimer?.cancel();
    unawaited(_closeConnection());
    super.dispose();
  }
}
