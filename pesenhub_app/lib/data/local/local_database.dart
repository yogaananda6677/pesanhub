import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../core/utils/pii_sanitizer.dart';

/// LocalDatabase manages SQLite connections, versioned migrations,
/// and relational storage for PesenHub POS and KDS.
/// Fulfills Issue #32 Acceptance Criteria #1, #3, and #4.
class LocalDatabase {
  static const int currentVersion = 10;
  static const String defaultDbName = 'pesenhub.db';

  final String? customPath;
  final DatabaseFactory? customFactory;

  Database? _database;

  LocalDatabase({this.customPath, this.customFactory});

  /// Provides active database connection or initializes a new one.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await initDatabase();
    return _database!;
  }

  /// Initializes the SQLite database connection.
  Future<Database> initDatabase({int targetVersion = currentVersion}) async {
    final String path;
    if (customPath != null) {
      path = customPath!;
    } else {
      final dbFolder = await (customFactory ?? databaseFactory)
          .getDatabasesPath();
      path = p.join(dbFolder, defaultDbName);
    }

    final factory = customFactory ?? databaseFactory;
    return await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: targetVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          await _createV1Schema(db);
          if (version >= 2) {
            await _migrateToV2(db);
          }
          if (version >= 3) {
            await _migrateToV3(db);
          }
          if (version >= 4) {
            await _migrateToV4(db);
          }
          if (version >= 5) {
            await _migrateToV5(db);
          }
          if (version >= 6) {
            await _migrateToV6(db);
          }
          if (version >= 7) {
            await _migrateToV7(db);
          }
          if (version >= 8) {
            await _migrateToV8(db);
          }
          if (version >= 9) {
            await _migrateToV9(db);
          }
          if (version >= 10) {
            await _migrateToV10(db);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2 && newVersion >= 2) {
            await _migrateToV2(db);
          }
          if (oldVersion < 3 && newVersion >= 3) {
            await _migrateToV3(db);
          }
          if (oldVersion < 4 && newVersion >= 4) {
            await _migrateToV4(db);
          }
          if (oldVersion < 5 && newVersion >= 5) {
            await _migrateToV5(db);
          }
          if (oldVersion < 6 && newVersion >= 6) {
            await _migrateToV6(db);
          }
          if (oldVersion < 7 && newVersion >= 7) {
            await _migrateToV7(db);
          }
          if (oldVersion < 8 && newVersion >= 8) {
            await _migrateToV8(db);
          }
          if (oldVersion < 9 && newVersion >= 9) {
            await _migrateToV9(db);
          }
          if (oldVersion < 10 && newVersion >= 10) {
            await _migrateToV10(db);
          }
        },
      ),
    );
  }

  /// v1 Schema definition: categories, menus, queue_orders, queue_order_items, sync_metadata.
  static Future<void> _createV1Schema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        is_active INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS menus (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        sku TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        price_amount INTEGER NOT NULL,
        is_available INTEGER NOT NULL,
        version INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        is_drink INTEGER NOT NULL,
        modifier_groups_json TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS queue_orders (
        id TEXT PRIMARY KEY,
        order_number TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        customer_phone_masked TEXT NOT NULL,
        source TEXT NOT NULL,
        order_status TEXT NOT NULL,
        payment_status TEXT NOT NULL,
        is_takeaway INTEGER NOT NULL,
        takeaway_notes TEXT,
        created_at TEXT NOT NULL,
        version INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS queue_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL,
        notes TEXT,
        is_drink INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES queue_orders (id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  /// v2 Schema migration: adds composite indexes and recent_customers table.
  static Future<void> _migrateToV2(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_menus_category_availability 
      ON menus (category_id, is_available);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_queue_orders_status_created 
      ON queue_orders (order_status, created_at);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recent_customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        masked_phone TEXT NOT NULL,
        last_order_at TEXT NOT NULL
      );
    ''');
  }

  static Future<void> _migrateToV6(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(menus)');
    final names = columns.map((row) => row['name'] as String).toSet();
    if (!names.contains('hpp_amount')) {
      await db.execute('ALTER TABLE menus ADD COLUMN hpp_amount INTEGER;');
    }
    if (!names.contains('channel_prices_json')) {
      await db.execute(
        "ALTER TABLE menus ADD COLUMN channel_prices_json TEXT NOT NULL DEFAULT '[]';",
      );
    }

    // Remove the old showcase catalog that was previously written into the
    // operational cache. Real catalog data is always hydrated from Backend.
    await db.delete(
      'menus',
      where: 'id IN (?, ?, ?, ?, ?, ?)',
      whereArgs: const [
        'm-nasgor-spesial',
        'm-nasgor-gila',
        'm-nasgor-seafood',
        'm-es-teh',
        'm-es-jeruk',
        'm-kerupuk',
      ],
    );
    await db.delete(
      'categories',
      where: 'id IN (?, ?, ?)',
      whereArgs: const ['cat-makanan', 'cat-minuman', 'cat-tambahan'],
    );
  }

  static Future<void> _migrateToV7(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(menus)');
    final names = columns.map((row) => row['name'] as String).toSet();
    if (!names.contains('product_type')) {
      await db.execute(
        "ALTER TABLE menus ADD COLUMN product_type TEXT NOT NULL DEFAULT 'MARTABAK_TELUR';",
      );
    }
    if (!names.contains('image_url')) {
      await db.execute('ALTER TABLE menus ADD COLUMN image_url TEXT;');
    }
  }

  static Future<void> _migrateToV8(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS menu_image_cache (
        menu_id TEXT PRIMARY KEY,
        source_url TEXT NOT NULL,
        local_path TEXT NOT NULL,
        byte_size INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_menu_image_cache_source_url
      ON menu_image_cache (source_url);
    ''');
  }

  static Future<void> _migrateToV9(Database db) async {
    final queueCols = await db.rawQuery('PRAGMA table_info(queue_orders)');
    final queueNames = queueCols.map((row) => row['name'] as String).toSet();
    if (!queueNames.contains('branch_id')) {
      await db.execute('ALTER TABLE queue_orders ADD COLUMN branch_id TEXT;');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_queue_orders_branch 
        ON queue_orders (branch_id);
      ''');
    }

    final outboxCols = await db.rawQuery('PRAGMA table_info(outbox_mutations)');
    final outboxNames = outboxCols.map((row) => row['name'] as String).toSet();
    if (!outboxNames.contains('branch_id')) {
      await db.execute(
        'ALTER TABLE outbox_mutations ADD COLUMN branch_id TEXT;',
      );
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_outbox_branch 
        ON outbox_mutations (branch_id);
      ''');
    }
  }

  static Future<void> _migrateToV10(Database db) async {
    // Recreate outbox_mutations without UNIQUE constraint on client_order_id.
    // This allows an order to queue multiple sequential mutations (e.g. CREATE_ORDER, then UPDATE_STATUS).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox_mutations_new (
        id TEXT PRIMARY KEY,
        idempotency_key TEXT NOT NULL UNIQUE,
        client_order_id TEXT NOT NULL,
        mutation_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_attempted_at TEXT,
        next_retry_at TEXT,
        server_order_id TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL,
        branch_id TEXT
      );
    ''');
    final cols = await db.rawQuery('PRAGMA table_info(outbox_mutations)');
    final colNames = cols.map((row) => row['name'] as String).toSet();
    final hasBranch = colNames.contains('branch_id');
    if (hasBranch) {
      await db.execute('''
        INSERT OR IGNORE INTO outbox_mutations_new (
          id, idempotency_key, client_order_id, mutation_type, payload_json,
          sync_status, retry_count, last_attempted_at, next_retry_at,
          server_order_id, error_message, created_at, branch_id
        )
        SELECT 
          id, idempotency_key, client_order_id, mutation_type, payload_json,
          sync_status, retry_count, last_attempted_at, next_retry_at,
          server_order_id, error_message, created_at, branch_id
        FROM outbox_mutations;
      ''');
    } else {
      await db.execute('''
        INSERT OR IGNORE INTO outbox_mutations_new (
          id, idempotency_key, client_order_id, mutation_type, payload_json,
          sync_status, retry_count, last_attempted_at, next_retry_at,
          server_order_id, error_message, created_at
        )
        SELECT 
          id, idempotency_key, client_order_id, mutation_type, payload_json,
          sync_status, retry_count, last_attempted_at, next_retry_at,
          server_order_id, error_message, created_at
        FROM outbox_mutations;
      ''');
    }
    await db.execute('DROP TABLE outbox_mutations;');
    await db.execute(
      'ALTER TABLE outbox_mutations_new RENAME TO outbox_mutations;',
    );
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_status_retry 
      ON outbox_mutations (sync_status, next_retry_at);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_client_order_id 
      ON outbox_mutations (client_order_id);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_branch 
      ON outbox_mutations (branch_id);
    ''');
  }

  /// v3 Schema migration: adds outbox_mutations table and sync indexes.
  static Future<void> _migrateToV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox_mutations (
        id TEXT PRIMARY KEY,
        idempotency_key TEXT NOT NULL UNIQUE,
        client_order_id TEXT NOT NULL,
        mutation_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_attempted_at TEXT,
        next_retry_at TEXT,
        server_order_id TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_status_retry 
      ON outbox_mutations (sync_status, next_retry_at);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_client_order_id 
      ON outbox_mutations (client_order_id);
    ''');
  }

  /// v4 Schema migration: adds conflict_logs table for sanitized audit records.
  static Future<void> _migrateToV4(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conflict_logs (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        client_order_id TEXT,
        conflict_type TEXT NOT NULL,
        resolution_strategy TEXT NOT NULL,
        client_version INTEGER NOT NULL,
        server_version INTEGER NOT NULL,
        resolved_payload_json TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_conflict_logs_order 
      ON conflict_logs (order_id);
    ''');
  }

  static Future<void> _migrateToV5(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(categories)');
    if (!columns.any((row) => row['name'] == 'version')) {
      await db.execute(
        'ALTER TABLE categories ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
      );
    }
  }

  /// Sets metadata entry with validation against sensitive tokens/secrets.
  Future<void> setMetadata(String key, String value) async {
    PiiSanitizer.validateMetadataKey(key);
    final db = await database;
    await db.insert('sync_metadata', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retrieves metadata entry by key, or null if not found.
  Future<String?> getMetadata(String key) async {
    final db = await database;
    final rows = await db.query(
      'sync_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Clears all tables for test resets.
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('conflict_logs');
      await txn.delete('outbox_mutations');
      await txn.delete('queue_order_items');
      await txn.delete('queue_orders');
      await txn.delete('menus');
      await txn.delete('categories');
      await txn.delete('recent_customers');
      await txn.delete('sync_metadata');
    });
  }

  /// Closes database connection.
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}
