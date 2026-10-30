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
    late LocalDatabase localDb;

    setUp(() async {
      localDb = LocalDatabase(
        customPath: inMemoryDatabasePath,
        customFactory: databaseFactoryFfi,
      );
    });

    tearDown(() async {
      await localDb.close();
    });

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
                    },
                  ],
                }),
                200,
              );
            }
            if (req.method == 'GET' &&
                req.url.path == '/api/v1/branches/b-01') {
              return http.Response(
                jsonEncode({
                  'data': {
                    'id': 'b-01',
                    'name': 'Cabang Utama Genteng',
                    'address': 'Jl. Gajah Mada No. 12',
                    'phone': '081234567890',
                    'open_time': '16:00',
                    'close_time': '23:30',
                    'open_days': 'SENIN,SELASA,RABU,KAMIS,JUMAT,SABTU,MINGGU',
                    'is_open': true,
                  },
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
            home: Scaffold(
              body: OutletOperationalView(
                apiClient: client,
                localDatabase: localDb,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Outlet & Operasional'), findsOneWidget);
        expect(find.text('Cabang Utama Genteng'), findsWidgets);
        expect(find.text('Jl. Gajah Mada No. 12'), findsOneWidget);
        expect(find.text('16:00 - 23:30 WIB'), findsOneWidget);
        expect(find.text('Setiap Hari (Senin - Minggu)'), findsOneWidget);
        expect(find.text('BUKA'), findsOneWidget);
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
          home: Scaffold(
            body: OutletOperationalView(
              apiClient: client,
              localDatabase: localDb,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('BUKA'), findsOneWidget);

      // Tap the Switch to toggle status
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(updatedIsOpen, 'false');
      expect(find.text('TUTUP'), findsOneWidget);
    });

    testWidgets('falls back to local cached metadata when offline', (
      tester,
    ) async {
      await localDb.setMetadata(
        'cached_branch_operational',
        jsonEncode({
          'id': 'b-cached',
          'name': 'Cabang Offline Rogojampi',
          'address': 'Jl. Rogojampi Indah No. 5',
          'phone': '081987654321',
          'open_time': '17:00',
          'close_time': '22:00',
          'open_days': 'SENIN,SELASA,RABU',
          'is_open': false,
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: OutletOperationalView(
              apiClient: null,
              localDatabase: localDb,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cabang Offline Rogojampi'), findsWidgets);
      expect(find.text('Jl. Rogojampi Indah No. 5'), findsOneWidget);
      expect(find.text('17:00 - 22:00 WIB'), findsOneWidget);
      expect(find.text('TUTUP'), findsOneWidget);
    });
  });
}
