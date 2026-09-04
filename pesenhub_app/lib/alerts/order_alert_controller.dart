import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/utils/event_deduplicator.dart';

enum AlertPermission { unknown, granted, denied }

class OrderAlert {
  final String eventId;
  final String orderId;
  final String orderNumber;
  final String kind;
  final String message;
  const OrderAlert({
    required this.eventId,
    required this.orderId,
    required this.orderNumber,
    required this.kind,
    required this.message,
  });
}

abstract class LocalNotificationGateway {
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<void> show(OrderAlert alert);
}

abstract class AlertFeedback {
  Future<void> play();
}

class SystemAlertFeedback implements AlertFeedback {
  @override
  Future<void> play() async {
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
  }
}

class FlutterLocalNotificationGateway implements LocalNotificationGateway {
  final FlutterLocalNotificationsPlugin plugin;
  FlutterLocalNotificationGateway([FlutterLocalNotificationsPlugin? plugin])
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() => plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  @override
  Future<bool> requestPermission() async {
    final android = await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final ios = await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? false;
  }

  @override
  Future<void> show(OrderAlert alert) => plugin.show(
    id: alert.eventId.hashCode & 0x7fffffff,
    title: alert.kind == 'NEW_ORDER'
        ? 'Pesanan baru ${alert.orderNumber}'
        : 'Status ${alert.orderNumber} berubah',
    body: alert.message,
    payload: alert.orderId,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'order_alerts',
        'Alert Pesanan',
        channelDescription: 'Pesanan baru dan perubahan status',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    ),
  );
}

class OrderAlertController extends ChangeNotifier {
  final LocalNotificationGateway notifications;
  final EventDeduplicator _dedupe;
  final AlertFeedback feedback;
  final Duration throttleWindow;
  final DateTime Function() now;
  final Map<String, DateTime> _lastAlertAt = {};
  OrderAlert? _activeAlert;
  OrderAlert? _pendingFallback;
  AlertPermission _permission = AlertPermission.unknown;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  OrderAlertController({
    LocalNotificationGateway? notifications,
    EventDeduplicator? deduplicator,
    AlertFeedback? feedback,
    this.throttleWindow = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : notifications = notifications ?? FlutterLocalNotificationGateway(),
       feedback = feedback ?? SystemAlertFeedback(),
       _dedupe = deduplicator ?? EventDeduplicator(),
       now = now ?? DateTime.now;

  OrderAlert? get activeAlert => _activeAlert;
  AlertPermission get permission => _permission;

  Future<void> initialize() async {
    try {
      await notifications.initialize();
    } catch (_) {}
  }

  Future<bool> requestPermission() async {
    try {
      _permission = await notifications.requestPermission()
          ? AlertPermission.granted
          : AlertPermission.denied;
    } catch (_) {
      _permission = AlertPermission.denied;
    }
    notifyListeners();
    return _permission == AlertPermission.granted;
  }

  Future<bool> handle(OrderAlert alert) async {
    if (!_dedupe.shouldProcess(alert.eventId)) return false;
    final throttleKey = '${alert.orderId}:${alert.kind}:${alert.message}';
    final instant = now();
    final previous = _lastAlertAt[throttleKey];
    if (previous != null && instant.difference(previous) < throttleWindow) {
      return false;
    }
    _lastAlertAt[throttleKey] = instant;
    if (_lifecycle == AppLifecycleState.resumed) {
      _activeAlert = alert;
      notifyListeners();
      try {
        await feedback.play();
      } catch (_) {
        // The visual alert remains available when sound/haptics are unavailable.
      }
    } else if (_permission == AlertPermission.granted) {
      try {
        await notifications.show(alert);
      } catch (_) {
        _pendingFallback = alert;
      }
    } else {
      _pendingFallback = alert;
    }
    return true;
  }

  void setLifecycle(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed && _pendingFallback != null) {
      _activeAlert = _pendingFallback;
      _pendingFallback = null;
      notifyListeners();
    }
  }

  void dismiss() {
    if (_activeAlert == null) return;
    _activeAlert = null;
    notifyListeners();
  }
}
