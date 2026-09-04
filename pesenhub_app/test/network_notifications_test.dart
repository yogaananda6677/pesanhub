import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/alerts/order_alert_controller.dart';
import 'package:pesenhub_app/connectivity/connectivity_controller.dart';
import 'package:pesenhub_app/queue/controllers/queue_controller.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/shell/app_shell.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/connectivity_badge.dart';

class FakeConnectivity implements ConnectivityMonitor {
  final StreamController<bool> stream = StreamController<bool>.broadcast();
  bool online;
  FakeConnectivity(this.online);
  @override
  Future<bool> isOnline() async => online;
  @override
  Stream<bool> get changes => stream.stream;
  void emit(bool value) {
    online = value;
    stream.add(value);
  }

  Future<void> close() => stream.close();
}

class FakeNotifications implements LocalNotificationGateway {
  bool granted;
  int shown = 0;
  int initialized = 0;
  FakeNotifications({this.granted = false});
  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  Future<bool> requestPermission() async => granted;
  @override
  Future<void> show(OrderAlert alert) async {
    shown++;
  }
}

class FakeFeedback implements AlertFeedback {
  int played = 0;
  @override
  Future<void> play() async {
    played++;
  }
}

const eventA = OrderAlert(
  eventId: 'event-1',
  orderId: 'order-1',
  orderNumber: '#101',
  kind: 'NEW_ORDER',
  message: 'Pesanan baru masuk.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'connectivity emits online, offline, and syncing without color-only state',
    () async {
      final fake = FakeConnectivity(true);
      final controller = ConnectivityController(monitor: fake);
      await controller.start();
      expect(controller.state, OperationalConnectionState.online);
      fake.emit(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, OperationalConnectionState.offline);
      controller.setSyncing(true);
      expect(controller.state, OperationalConnectionState.syncing);
      controller.setSyncing(false);
      expect(controller.state, OperationalConnectionState.offline);
      controller.dispose();
      await fake.close();
    },
  );

  test('dedupe and throttle allow at most one device alert', () async {
    final gateway = FakeNotifications();
    final instant = DateTime(2026);
    final alerts = OrderAlertController(
      notifications: gateway,
      feedback: FakeFeedback(),
      now: () => instant,
    );
    expect(await alerts.handle(eventA), isTrue);
    expect(await alerts.handle(eventA), isFalse);
    expect(
      await alerts.handle(
        const OrderAlert(
          eventId: 'event-2',
          orderId: 'order-1',
          orderNumber: '#101',
          kind: 'NEW_ORDER',
          message: 'Pesanan baru masuk.',
        ),
      ),
      isFalse,
    );
  });

  test('background permission and denied fallback follow lifecycle', () async {
    final granted = FakeNotifications(granted: true);
    final alerts = OrderAlertController(
      notifications: granted,
      feedback: FakeFeedback(),
    );
    await alerts.initialize();
    expect(await alerts.requestPermission(), isTrue);
    alerts.setLifecycle(AppLifecycleState.paused);
    expect(await alerts.handle(eventA), isTrue);
    expect(granted.shown, 1);
    expect(alerts.activeAlert, isNull);
    final denied = OrderAlertController(
      notifications: FakeNotifications(),
      feedback: FakeFeedback(),
    );
    await denied.requestPermission();
    denied.setLifecycle(AppLifecycleState.paused);
    await denied.handle(eventA);
    expect(denied.activeAlert, isNull);
    denied.setLifecycle(AppLifecycleState.resumed);
    expect(denied.activeAlert, eventA);
  });

  testWidgets('indicator renders text, icon, semantics on mobile and tablet', (
    tester,
  ) async {
    final fake = FakeConnectivity(false);
    final controller = ConnectivityController(
      monitor: fake,
      initiallyOnline: false,
    );
    final semantics = tester.ensureSemantics();
    for (final size in [const Size(400, 800), const Size(1024, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: ConnectivityBadge(controller: controller)),
        ),
      );
      expect(find.text('Offline'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Status koneksi: Offline',
        ),
        findsOneWidget,
      );
    }
    semantics.dispose();
    controller.dispose();
    await fake.close();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('permission denial keeps non-blocking heads-up alert in app', (
    tester,
  ) async {
    final fakeConnectivity = FakeConnectivity(true);
    final connectivity = ConnectivityController(monitor: fakeConnectivity);
    final alerts = OrderAlertController(
      notifications: FakeNotifications(),
      feedback: FakeFeedback(),
    );
    await alerts.requestPermission();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: AppShell(
          connectivityController: connectivity,
          alertController: alerts,
        ),
      ),
    );
    await alerts.handle(eventA);
    await tester.pump();
    expect(find.byKey(const Key('order-heads-up-alert')), findsOneWidget);
    expect(find.text('#101'), findsOneWidget);
    expect(
      find.byKey(const Key('notification-permission-button')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Tutup alert'));
    await tester.pump();
    expect(find.byKey(const Key('order-heads-up-alert')), findsNothing);
    connectivity.dispose();
    alerts.dispose();
    await fakeConnectivity.close();
  });

  test(
    'queue event integration alerts once and never exposes customer PII',
    () async {
      final alerts = OrderAlertController(
        notifications: FakeNotifications(),
        feedback: FakeFeedback(),
        now: () => DateTime(2026),
      );
      final queue = QueueController(alertController: alerts);
      final order = QueueOrder(
        id: 'order-1',
        orderNumber: '#101',
        customerName: 'Private Name',
        customerPhone: '081234567890',
        source: 'CUSTOMER_WEB',
        orderStatus: 'PENDING',
        paymentStatus: 'UNPAID',
        createdAt: DateTime(2026),
      );
      queue.upsertOrder(order, eventId: 'socket-1');
      await Future<void>.delayed(Duration.zero);
      expect(alerts.activeAlert?.orderNumber, '#101');
      expect(alerts.activeAlert?.message, isNot(contains('Private Name')));
      queue.upsertOrder(order, eventId: 'socket-1');
      expect(queue.totalCount, 1);
    },
  );
}
