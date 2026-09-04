import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pesenhub_app/core/utils/pii_sanitizer.dart';
import 'package:pesenhub_app/data/local/cold_start_cache_service.dart';
import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/data/local/menu_local_repository.dart';
import 'package:pesenhub_app/data/local/queue_local_repository.dart';
import 'package:pesenhub_app/menu/models/menu_category.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:pesenhub_app/menu/models/menu_modifier_group.dart';
import 'package:pesenhub_app/menu/models/menu_option.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';
import 'package:pesenhub_app/widgets/cache_status_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Acceptance Criteria #1: ADR & SQLite Engine Initialization', () {
    test(
      'Initializes SQLite database with foreign keys enabled in-memory',
      () async {
        final localDb = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );

        final db = await localDb.database;
        expect(db.isOpen, isTrue);

        final pragmaRows = await db.rawQuery('PRAGMA foreign_keys;');
        expect(pragmaRows.first.values.first, equals(1));

        await localDb.close();
      },
    );
  });

  group('Acceptance Criteria #2: Cold Start Caching & Stale Marker', () {
    late LocalDatabase localDb;
    late MenuLocalRepository menuRepo;
    late QueueLocalRepository queueRepo;
    late ColdStartCacheService coldStartService;

    setUp(() async {
      localDb = LocalDatabase(
        customPath: inMemoryDatabasePath,
        customFactory: databaseFactoryFfi,
      );
      menuRepo = MenuLocalRepository(localDb);
      queueRepo = QueueLocalRepository(localDb);
      coldStartService = ColdStartCacheService(
        localDb: localDb,
        menuRepo: menuRepo,
        queueRepo: queueRepo,
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    test('Cold start reads empty state when no cache exists', () async {
      final snapshot = await coldStartService.hydrate();

      expect(snapshot.hasCachedData, isFalse);
      expect(snapshot.isStale, isTrue);
      expect(snapshot.catalog.data.items, isEmpty);
      expect(snapshot.queue.data, isEmpty);
    });

    test('Cold start reads fresh cached catalog and queue orders', () async {
      final now = DateTime.now();

      await menuRepo.saveCatalog(
        categories: [
          const MenuCategory(id: 'cat-1', name: 'Makanan', sortOrder: 1),
        ],
        items: [
          const MenuItem(
            id: 'menu-1',
            categoryId: 'cat-1',
            sku: 'NASGOR-01',
            name: 'Nasi Goreng Spesial',
            priceAmount: 25000,
            modifierGroups: [
              MenuModifierGroup(
                id: 'mod-1',
                code: 'SPICE',
                name: 'Level Pedas',
                options: [MenuOption(id: 'opt-1', code: 'L1', name: 'Sedang')],
              ),
            ],
          ),
        ],
        cachedAt: now,
      );

      await queueRepo.saveOrders(
        orders: [
          QueueOrder(
            id: 'ord-01',
            orderNumber: '#ORD-01',
            customerName: 'Budi',
            customerPhone: '081234567890',
            source: 'WHATSAPP',
            orderStatus: 'PENDING',
            paymentStatus: 'PAID',
            createdAt: now,
            items: const [
              QueueOrderItem(
                name: 'Nasi Goreng Spesial',
                quantity: 1,
                unitPrice: 25000,
              ),
            ],
          ),
        ],
        cachedAt: now,
      );

      final snapshot = await coldStartService.hydrate(
        staleThreshold: const Duration(minutes: 15),
      );

      expect(snapshot.hasCachedData, isTrue);
      expect(snapshot.isStale, isFalse);
      expect(snapshot.catalog.data.categories.length, equals(1));
      expect(snapshot.catalog.data.items.length, equals(1));
      expect(snapshot.catalog.data.items.first.hasModifiers, isTrue);
      expect(snapshot.queue.data.length, equals(1));
      expect(snapshot.queue.data.first.orderNumber, equals('#ORD-01'));
      expect(snapshot.queue.data.first.items.length, equals(1));
    });

    test('Cold start flags data as stale when exceeding threshold', () async {
      final pastTime = DateTime.now().subtract(const Duration(minutes: 25));

      await menuRepo.saveCatalog(
        categories: [const MenuCategory(id: 'cat-1', name: 'Makanan')],
        items: [
          const MenuItem(
            id: 'menu-1',
            categoryId: 'cat-1',
            sku: 'NASGOR-01',
            name: 'Nasi Goreng',
            priceAmount: 20000,
          ),
        ],
        cachedAt: pastTime,
      );

      await queueRepo.saveOrders(orders: [], cachedAt: pastTime);

      final snapshot = await coldStartService.hydrate(
        staleThreshold: const Duration(minutes: 15),
      );

      expect(snapshot.hasCachedData, isTrue);
      expect(snapshot.isStale, isTrue);
      expect(snapshot.catalog.isStale, isTrue);
      expect(snapshot.catalog.formattedCachedAt, isNotEmpty);
    });

    test(
      'Seeding sample data populates initial catalog and queue with PII masking',
      () async {
        await coldStartService.seedInitialSampleDataIfEmpty();

        final snapshot = await coldStartService.hydrate();
        expect(snapshot.hasCachedData, isTrue);
        expect(snapshot.catalog.data.items.length, greaterThanOrEqualTo(6));
        expect(snapshot.queue.data.length, greaterThanOrEqualTo(2));

        // Check all seeded phone numbers are masked
        for (final order in snapshot.queue.data) {
          expect(order.customerPhone.contains('*'), isTrue);
        }
      },
    );
  });

  group('Acceptance Criteria #3: Local Migration v1 to v2 Without Record Loss', () {
    test('Migrates from v1 to v2 preserving existing fixture records', () async {
      final dbFolder = await databaseFactoryFfi.getDatabasesPath();
      final migrationDbPath = p.join(dbFolder, 'test_migration.db');
      await databaseFactoryFfi.deleteDatabase(migrationDbPath);

      // Open database targeting v1
      final localDbV1 = LocalDatabase(
        customPath: migrationDbPath,
        customFactory: databaseFactoryFfi,
      );

      final dbV1 = await localDbV1.initDatabase(targetVersion: 1);

      // Insert fixture data into v1 tables
      await dbV1.insert('categories', {
        'id': 'cat-fixture-1',
        'name': 'Makanan Utama',
        'sort_order': 1,
        'is_active': 1,
      });

      await dbV1.insert('menus', {
        'id': 'menu-fixture-1',
        'category_id': 'cat-fixture-1',
        'sku': 'NASGOR-FIX-01',
        'name': 'Nasi Goreng Fixture',
        'description': 'Resep legendaris',
        'price_amount': 28000,
        'is_available': 1,
        'version': 1,
        'sort_order': 1,
        'is_drink': 0,
        'modifier_groups_json': null,
      });

      await dbV1.insert('queue_orders', {
        'id': 'ord-fixture-1',
        'order_number': '#ORD-FIX-01',
        'customer_name': 'Pelanggan Tetap',
        'customer_phone_masked': '0812****9999',
        'source': 'WHATSAPP',
        'order_status': 'PENDING',
        'payment_status': 'PAID',
        'is_takeaway': 0,
        'takeaway_notes': null,
        'created_at': DateTime.now().toIso8601String(),
        'version': 1,
      });

      await dbV1.insert('queue_order_items', {
        'order_id': 'ord-fixture-1',
        'name': 'Nasi Goreng Fixture',
        'quantity': 2,
        'unit_price': 28000,
        'notes': 'Pedas level 1',
        'is_drink': 0,
      });

      await dbV1.insert('sync_metadata', {
        'key': 'catalog_last_cached_at',
        'value': '2026-09-04T07:00:00.000Z',
        'updated_at': '2026-09-04T07:00:00.000Z',
      });

      // Verify v1 record counts before upgrade
      final countCategoriesV1 = Sqflite.firstIntValue(
        await dbV1.rawQuery('SELECT COUNT(*) FROM categories'),
      );
      final countMenusV1 = Sqflite.firstIntValue(
        await dbV1.rawQuery('SELECT COUNT(*) FROM menus'),
      );
      final countOrdersV1 = Sqflite.firstIntValue(
        await dbV1.rawQuery('SELECT COUNT(*) FROM queue_orders'),
      );
      final countItemsV1 = Sqflite.firstIntValue(
        await dbV1.rawQuery('SELECT COUNT(*) FROM queue_order_items'),
      );

      expect(countCategoriesV1, equals(1));
      expect(countMenusV1, equals(1));
      expect(countOrdersV1, equals(1));
      expect(countItemsV1, equals(1));

      // Close v1 database connection cleanly
      await dbV1.close();

      // Now upgrade schema to v2 by reopening the same database file targeting v2
      final localDbV2 = LocalDatabase(
        customPath: migrationDbPath,
        customFactory: databaseFactoryFfi,
      );
      final dbV2 = await localDbV2.initDatabase(targetVersion: 2);

      // Verify all fixture records are preserved without data loss
      final countCategoriesV2 = Sqflite.firstIntValue(
        await dbV2.rawQuery('SELECT COUNT(*) FROM categories'),
      );
      final countMenusV2 = Sqflite.firstIntValue(
        await dbV2.rawQuery('SELECT COUNT(*) FROM menus'),
      );
      final countOrdersV2 = Sqflite.firstIntValue(
        await dbV2.rawQuery('SELECT COUNT(*) FROM queue_orders'),
      );
      final countItemsV2 = Sqflite.firstIntValue(
        await dbV2.rawQuery('SELECT COUNT(*) FROM queue_order_items'),
      );

      expect(countCategoriesV2, equals(1));
      expect(countMenusV2, equals(1));
      expect(countOrdersV2, equals(1));
      expect(countItemsV2, equals(1));

      // Verify row details in v2
      final menuRow = (await dbV2.query(
        'menus',
        where: 'id = ?',
        whereArgs: ['menu-fixture-1'],
      )).first;
      expect(menuRow['name'], equals('Nasi Goreng Fixture'));
      expect(menuRow['price_amount'], equals(28000));

      final orderRow = (await dbV2.query(
        'queue_orders',
        where: 'id = ?',
        whereArgs: ['ord-fixture-1'],
      )).first;
      expect(orderRow['customer_name'], equals('Pelanggan Tetap'));
      expect(orderRow['customer_phone_masked'], equals('0812****9999'));

      // Verify v2 new indexes are created
      final indexes = await dbV2.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN ('idx_menus_category_availability', 'idx_queue_orders_status_created')",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_menus_category_availability'));
      expect(indexNames, contains('idx_queue_orders_status_created'));

      // Verify v2 new table recent_customers exists and is operable
      await dbV2.insert('recent_customers', {
        'id': 'cust-pelanggan_tetap',
        'name': 'Pelanggan Tetap',
        'masked_phone': '0812****9999',
        'last_order_at': DateTime.now().toIso8601String(),
      });

      final recentCustomers = await dbV2.query('recent_customers');
      expect(recentCustomers.length, equals(1));
      expect(recentCustomers.first['name'], equals('Pelanggan Tetap'));

      await dbV2.close();
      await databaseFactoryFfi.deleteDatabase(migrationDbPath);
    });
  });

  group(
    'Acceptance Criteria #4: PII Redaction & Storage Security (Invariant 11)',
    () {
      late LocalDatabase localDb;
      late QueueLocalRepository queueRepo;

      setUp(() {
        localDb = LocalDatabase(
          customPath: inMemoryDatabasePath,
          customFactory: databaseFactoryFfi,
        );
        queueRepo = QueueLocalRepository(localDb);
      });

      tearDown(() async {
        await localDb.close();
      });

      test('PiiSanitizer masks various phone formats accurately', () {
        expect(PiiSanitizer.maskPhone('081234567890'), equals('0812****7890'));
        expect(
          PiiSanitizer.maskPhone('0857-1122-3344'),
          equals('0857****3344'),
        );
        expect(PiiSanitizer.maskPhone('0812****7890'), equals('0812****7890'));
        expect(PiiSanitizer.maskPhone('Kasir'), equals('Kasir'));
        expect(PiiSanitizer.maskPhone(''), equals(''));
        expect(PiiSanitizer.maskPhone(null), equals(''));
      });

      test(
        'Raw customer phone numbers are sanitized before SQLite persistence',
        () async {
          await queueRepo.saveOrders(
            orders: [
              QueueOrder(
                id: 'ord-pii-1',
                orderNumber: '#ORD-PII',
                customerName: 'Ahmad Dahlan',
                customerPhone: '081298765432', // raw phone
                source: 'WHATSAPP',
                orderStatus: 'PENDING',
                paymentStatus: 'PAID',
                createdAt: DateTime.now(),
                items: const [],
              ),
            ],
          );

          final db = await localDb.database;
          final rows = await db.query(
            'queue_orders',
            where: 'id = ?',
            whereArgs: ['ord-pii-1'],
          );
          final storedPhone = rows.first['customer_phone_masked'] as String;

          expect(storedPhone, equals('0812****5432'));
          expect(
            storedPhone.contains('9876'),
            isFalse,
          ); // raw middle digits must never be present
        },
      );

      test(
        'Prohibits storing auth tokens and sensitive credentials in sync_metadata',
        () async {
          // Benign keys must succeed
          await localDb.setMetadata(
            'last_sync_timestamp',
            '2026-09-04T07:00:00Z',
          );
          await localDb.setMetadata('device_id', 'pos-pos-terminal-01');

          final timestamp = await localDb.getMetadata('last_sync_timestamp');
          expect(timestamp, equals('2026-09-04T07:00:00Z'));

          // Sensitive keys must be rejected with ArgumentError
          expect(
            () => localDb.setMetadata('auth_token', 'jwt.secret.token'),
            throwsA(isA<ArgumentError>()),
          );
          expect(
            () => localDb.setMetadata('refresh_token', 'jwt.refresh.token'),
            throwsA(isA<ArgumentError>()),
          );
          expect(
            () => localDb.setMetadata('user_password', 'p@ssword123'),
            throwsA(isA<ArgumentError>()),
          );
          expect(
            () => localDb.setMetadata('api_secret_key', 'supersecret'),
            throwsA(isA<ArgumentError>()),
          );
          expect(
            () => localDb.setMetadata('bearer_token', 'Bearer eyJhbGciOi...'),
            throwsA(isA<ArgumentError>()),
          );
        },
      );
    },
  );

  group(
    'Acceptance Criteria #5: Responsive UI Cache States on Mobile & Tablet',
    () {
      testWidgets('Renders loading state with progress indicator', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CacheStatusView(status: CacheViewStatus.loading),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Memuat data dari database lokal...'), findsOneWidget);
      });

      testWidgets(
        'Renders stale cache banner with formatted time and refresh action',
        (tester) async {
          bool refreshTapped = false;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CacheStatusView(
                  status: CacheViewStatus.stale,
                  cachedAtFormatted: '12:30',
                  onRefresh: () => refreshTapped = true,
                  child: const Text('Cached Content Visible'),
                ),
              ),
            ),
          );

          expect(find.byKey(const Key('stale-cache-banner')), findsOneWidget);
          expect(
            find.textContaining(
              'Mode Offline: Menampilkan data cache lokal (Terakhir disimpan: 12:30)',
            ),
            findsOneWidget,
          );
          expect(find.text('Cached Content Visible'), findsOneWidget);

          await tester.tap(find.byIcon(Icons.refresh_rounded));
          await tester.pump();
          expect(refreshTapped, isTrue);
        },
      );

      testWidgets('Renders empty cache state with sync action', (tester) async {
        bool syncTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CacheStatusView(
                status: CacheViewStatus.empty,
                onRefresh: () => syncTapped = true,
              ),
            ),
          ),
        );

        expect(find.text('Database Lokal Kosong'), findsOneWidget);
        expect(find.text('Sinkronkan Sekarang'), findsOneWidget);

        await tester.tap(find.text('Sinkronkan Sekarang'));
        await tester.pump();
        expect(syncTapped, isTrue);
      });

      testWidgets('Renders error state with retry action', (tester) async {
        bool retryTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CacheStatusView(
                status: CacheViewStatus.error,
                errorMessage: 'Database disk I/O failure',
                onRetry: () => retryTapped = true,
              ),
            ),
          ),
        );

        expect(find.text('Database disk I/O failure'), findsOneWidget);
        expect(find.text('Coba Lagi'), findsOneWidget);

        await tester.tap(find.text('Coba Lagi'));
        await tester.pump();
        expect(retryTapped, isTrue);
      });

      testWidgets('Renders without overflow on mobile viewport (390 x 844)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CacheStatusView(
                status: CacheViewStatus.stale,
                cachedAtFormatted: '14:15',
                child: Center(child: Text('Mobile Viewport')),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Mobile Viewport'), findsOneWidget);
      });

      testWidgets('Renders without overflow on tablet viewport (1024 x 768)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CacheStatusView(
                status: CacheViewStatus.stale,
                cachedAtFormatted: '14:15',
                child: Center(child: Text('Tablet Viewport')),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Tablet Viewport'), findsOneWidget);
      });
    },
  );
}
