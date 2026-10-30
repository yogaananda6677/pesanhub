import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/settings/views/outlet_operational_view.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OutletOperationalView Database Integration Tests', () {
    testWidgets(
      'renders branch operational data fetched from backend database',
      (tester) async {
        final client = PesenHubApiClient(
          config: ApiConfig(
            baseUri: Uri.parse('https://api.example.test/api/v1'),
          ),
          accessToken: () async => 'test-token',
          client: MockClient((req) async {
            if (req.method == 'GET' && req.url.path == '/api/v1/branches') {
              return http.Response(
                jsonEncode({
                  'data': [
                    {
                      'id': 'b-01',
                      'name': 'Cabang Utama Genteng',
                      'address': 'Jl. Gajah Mada No. 12',
                      'phone': '081234567890',
                      'open_time': '16:00',
                      'close_time': '23:30',
                      'open_days': 'SENIN,SELASA,RABU,KAMIS,JUMAT,SABTU,MINGGU',
                      'is_open': true,
                      'is_main': true,
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response('Not Found', 404);
          }),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: OutletOperationalView(apiClient: client)),
          ),
        );

        // Allow async _loadOperationalData to complete
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(find.text('Outlet & Operasional'), findsOneWidget);
        expect(find.text('Cabang Utama Genteng'), findsWidgets);
        expect(find.text('Jl. Gajah Mada No. 12'), findsWidgets);
        expect(find.text('16:00 - 23:30 WIB'), findsOneWidget);
        expect(find.text('Setiap Hari (Senin - Minggu)'), findsOneWidget);
        expect(find.text('Buka Sekarang'), findsOneWidget);
      },
    );

    testWidgets('toggles operational status switch and syncs to database', (
      tester,
    ) async {
      String? updatedIsOpen;
      final client = PesenHubApiClient(
        config: ApiConfig(
          baseUri: Uri.parse('https://api.example.test/api/v1'),
        ),
        accessToken: () async => 'test-token',
        client: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/api/v1/branches') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'b-01',
                    'name': 'Cabang Banyuwangi',
                    'address': 'Jl. Basuki Rahmat No. 1',
                    'phone': '0812345678',
                    'open_time': '16:00',
                    'close_time': '23:30',
                    'open_days': 'SENIN,SELASA',
                    'is_open': true,
                  },
                ],
              }),
              200,
            );
          }
          if (req.method == 'PATCH' &&
              req.url.path == '/api/v1/branches/b-01/operational') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            updatedIsOpen = body['is_open'].toString();
            return http.Response(
              jsonEncode({
                'message': 'updated',
                'branch': {'id': 'b-01', 'is_open': body['is_open']},
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: OutletOperationalView(apiClient: client)),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Buka Sekarang'), findsOneWidget);

      // Tap the Switch to toggle status
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(updatedIsOpen, 'false');
      expect(find.text('Tutup Sementara'), findsOneWidget);
    });

    test('LocalDatabase caches operational metadata for offline use', () async {
      final localDb = LocalDatabase(
        customPath: inMemoryDatabasePath,
        customFactory: databaseFactoryFfi,
      );

      final payload = jsonEncode({
        'id': 'b-cached',
        'name': 'Cabang Offline Rogojampi',
        'address': 'Jl. Rogojampi Indah No. 5',
        'phone': '081987654321',
        'open_time': '17:00',
        'close_time': '22:00',
        'open_days': 'SENIN,SELASA,RABU',
        'is_open': false,
      });

      await localDb.setMetadata('cached_branch_operational', payload);

      final cached = await localDb.getMetadata('cached_branch_operational');
      expect(cached, isNotNull);

      final map = jsonDecode(cached!) as Map<String, dynamic>;
      expect(map['id'], 'b-cached');
      expect(map['name'], 'Cabang Offline Rogojampi');
      expect(map['open_time'], '17:00');
      expect(map['close_time'], '22:00');
      expect(map['is_open'], isFalse);

      await localDb.close();
    });
  });
}
