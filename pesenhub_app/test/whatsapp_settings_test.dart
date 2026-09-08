import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesenhub_app/settings/controllers/whatsapp_settings_controller.dart';
import 'package:pesenhub_app/settings/models/whatsapp_settings_data.dart';
import 'package:pesenhub_app/settings/widgets/whatsapp_qr_dialog.dart';
import 'package:pesenhub_app/settings/widgets/whatsapp_settings_card.dart';
import 'package:pesenhub_app/shell/destination_views.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  group('WhatsAppSettingsData Model Tests', () {
    test('parses CONNECTED json properly', () {
      final jsonMap = {
        'is_connected': true,
        'status': 'CONNECTED',
        'gateway_state': 'UP',
        'phone_masked': '+62813****4134',
        'device_id': 'dev-123',
        'privacy_notice': 'Data privasi aman',
      };

      final data = WhatsAppSettingsData.fromJson(jsonMap);
      expect(data.isConnected, isTrue);
      expect(data.status, 'CONNECTED');
      expect(data.gatewayState, 'UP');
      expect(data.phoneMasked, '+62813****4134');
      expect(data.deviceId, 'dev-123');
      expect(data.privacyNotice, 'Data privasi aman');
    });

    test('parses DISCONNECTED and GATEWAY_DOWN json properly', () {
      final discData = WhatsAppSettingsData.fromJson({
        'is_connected': false,
        'status': 'DISCONNECTED',
        'gateway_state': 'UP',
      });
      expect(discData.isConnected, isFalse);
      expect(discData.status, 'DISCONNECTED');

      final downData = WhatsAppSettingsData.fromJson({
        'is_connected': false,
        'status': 'GATEWAY_DOWN',
        'gateway_state': 'DOWN',
      });
      expect(downData.isConnected, isFalse);
      expect(downData.status, 'GATEWAY_DOWN');
    });

    test('parses WhatsAppPairResult json properly', () {
      final pair = WhatsAppPairResult.fromJson({
        'is_already_logged_in': false,
        'status': 'SUCCESS',
        'device_id': 'test-dev',
        'qr_duration': 45,
        'qr_link': 'http://gowa/qr',
        'qr_proxy_url':
            'http://localhost:8080/api/v1/settings/whatsapp/qr-image?device_id=test-dev',
      });
      expect(pair.isAlreadyLoggedIn, isFalse);
      expect(pair.status, 'SUCCESS');
      expect(pair.deviceId, 'test-dev');
      expect(pair.qrDuration, 45);
      expect(pair.qrProxyUrl, contains('/qr-image'));
    });
  });

  group('WhatsAppSettingsController Tests', () {
    test('loads settings successfully using MockClient', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/settings/whatsapp') {
          return http.Response(
            jsonEncode({
              'is_connected': true,
              'status': 'CONNECTED',
              'gateway_state': 'UP',
              'phone_masked': '+62813****4134',
              'device_id': 'dev-001',
              'privacy_notice': 'Notifikasi otomatis transaksi.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final controller = WhatsAppSettingsController(
        baseUrl: 'http://test-server',
        client: mockClient,
      );

      await controller.loadSettings();

      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.data.isConnected, isTrue);
      expect(controller.data.status, 'CONNECTED');
      expect(controller.data.phoneMasked, '+62813****4134');
      expect(controller.data.deviceId, 'dev-001');

      controller.dispose();
    });

    test('handles pair and disconnect via controller callbacks', () async {
      bool paired = false;
      bool disconnected = false;

      final controller = WhatsAppSettingsController(
        initialData: const WhatsAppSettingsData(
          isConnected: false,
          status: 'DISCONNECTED',
          gatewayState: 'UP',
          deviceId: 'dev-001',
          phoneMasked: '-',
          privacyNotice: '',
        ),
        customPair: ({deviceId}) async {
          paired = true;
          return WhatsAppPairResult(
            isAlreadyLoggedIn: false,
            status: 'SUCCESS',
            deviceId: deviceId ?? 'dev-test',
            qrDuration: 30,
            qrLink: 'http://test/qr',
            qrProxyUrl: 'http://test/qr.png',
          );
        },
        customDisconnect: ({deviceId}) async {
          disconnected = true;
        },
      );

      final pairRes = await controller.requestPairing(deviceId: 'dev-custom');
      expect(paired, isTrue);
      expect(pairRes?.deviceId, 'dev-custom');
      expect(controller.isPairing, isTrue);
      expect(controller.remainingSeconds, 30);

      controller.stopPairing();
      expect(controller.isPairing, isFalse);

      await controller.disconnect(deviceId: 'dev-custom');
      expect(disconnected, isTrue);
      expect(controller.data.isConnected, isFalse);

      controller.dispose();
    });
  });

  group('WhatsAppSettingsCard & SettingsDestinationView Widget Tests', () {
    testWidgets(
      'renders connected state with masked phone and privacy notice',
      (tester) async {
        final controller = WhatsAppSettingsController(
          initialData: const WhatsAppSettingsData(
            isConnected: true,
            status: 'CONNECTED',
            gatewayState: 'UP',
            phoneMasked: '+62813****4134',
            deviceId: 'outlet-gowa-01',
            privacyNotice: 'PesenHub hanya mengakses sesi pesan keluar.',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: WhatsAppSettingsCard(controller: controller),
              ),
            ),
          ),
        );

        expect(find.text('Integrasi WhatsApp (GOWA)'), findsOneWidget);
        expect(find.text('Terhubung'), findsOneWidget);
        expect(find.text('+62813****4134'), findsOneWidget);
        expect(find.text('outlet-gowa-01'), findsOneWidget);
        expect(find.text('Privasi & Perlindungan Data'), findsOneWidget);
        expect(
          find.text('PesenHub hanya mengakses sesi pesan keluar.'),
          findsOneWidget,
        );
        expect(find.text('Putuskan'), findsOneWidget);

        controller.dispose();
      },
    );

    testWidgets('renders disconnected state with pair button', (tester) async {
      final controller = WhatsAppSettingsController(
        initialData: const WhatsAppSettingsData(
          isConnected: false,
          status: 'DISCONNECTED',
          gatewayState: 'UP',
          phoneMasked: '-',
          deviceId: 'outlet-gowa-01',
          privacyNotice: 'Belum terhubung',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: WhatsAppSettingsCard(controller: controller),
            ),
          ),
        ),
      );

      expect(find.text('Belum Terhubung'), findsOneWidget);
      expect(find.text('Hubungkan WhatsApp'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('renders gateway down state appropriately', (tester) async {
      final controller = WhatsAppSettingsController(
        initialData: const WhatsAppSettingsData(
          isConnected: false,
          status: 'GATEWAY_DOWN',
          gatewayState: 'DOWN',
          phoneMasked: '-',
          deviceId: '',
          privacyNotice: '',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: WhatsAppSettingsCard(controller: controller),
            ),
          ),
        ),
      );

      expect(find.text('Gateway Offline'), findsOneWidget);
      expect(find.text('Tidak Aktif'), findsOneWidget);

      controller.dispose();
    });

    testWidgets(
      'SettingsDestinationView contains WhatsAppSettingsCard and Outlet Info',
      (tester) async {
        final controller = WhatsAppSettingsController(
          initialData: const WhatsAppSettingsData(
            isConnected: true,
            status: 'CONNECTED',
            gatewayState: 'UP',
            phoneMasked: '+62813****4134',
            deviceId: 'outlet-gowa-01',
            privacyNotice: 'Privasi terjamin',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SettingsDestinationView(whatsAppController: controller),
            ),
          ),
        );

        expect(find.text('Integrasi WhatsApp (GOWA)'), findsOneWidget);
        expect(find.text('Informasi Outlet'), findsOneWidget);
        expect(find.text('Buka Katalog Design System'), findsOneWidget);

        controller.dispose();
      },
    );

    testWidgets('WhatsAppQrDialog shows steps and countdown', (tester) async {
      final controller = WhatsAppSettingsController(
        initialData: const WhatsAppSettingsData(
          isConnected: false,
          status: 'DISCONNECTED',
          gatewayState: 'UP',
          deviceId: '',
          phoneMasked: '-',
          privacyNotice: '',
        ),
        customPair: ({deviceId}) async {
          return const WhatsAppPairResult(
            isAlreadyLoggedIn: false,
            status: 'SUCCESS',
            deviceId: 'dev-qr-test',
            qrDuration: 30,
            qrLink: 'http://test/qr',
            qrProxyUrl: 'http://test/qr.png',
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: WhatsAppQrDialog(controller: controller)),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Hubungkan WhatsApp'), findsOneWidget);
      expect(
        find.textContaining('Buka aplikasi WhatsApp di HP outlet'),
        findsOneWidget,
      );
      expect(find.textContaining('Tautkan Perangkat'), findsOneWidget);
      expect(find.textContaining('detik'), findsOneWidget);

      controller.stopPairing();
      controller.dispose();
    });
  });
}
