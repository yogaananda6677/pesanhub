import 'package:sqflite/sqflite.dart';
import '../../core/utils/pii_sanitizer.dart';
import '../../queue/models/queue_order.dart';
import '../../queue/models/queue_order_item.dart';
import 'local_database.dart';
import 'models/cached_result.dart';

/// QueueLocalRepository manages persistent SQLite storage and caching
/// for the unified order queue and KDS orders, strictly enforcing
/// Invariant 11 (PII Sanitization).
/// Fulfills Issue #32 Acceptance Criteria #1, #2, and #4.
class QueueLocalRepository {
  final LocalDatabase _localDb;

  static const String metadataKeyLastCached = 'queue_last_cached_at';

  QueueLocalRepository(this._localDb);

  /// Saves orders and line items into SQLite within an atomic transaction.
  /// Automatically masks raw customer phone numbers before persistence.
  Future<void> saveOrders({
    required List<QueueOrder> orders,
    DateTime? cachedAt,
  }) async {
    final db = await _localDb.database;
    final timestamp = (cachedAt ?? DateTime.now()).toIso8601String();

    await db.transaction((txn) async {
      // Clear existing queue snapshot
      await txn.delete('queue_order_items');
      await txn.delete('queue_orders');

      for (final order in orders) {
        // Enforce PII Sanitization (Invariant 11)
        final maskedPhone = PiiSanitizer.maskPhone(order.customerPhone);

        await txn.insert(
          'queue_orders',
          {
            'id': order.id,
            'order_number': order.orderNumber,
            'customer_name': order.customerName,
            'customer_phone_masked': maskedPhone,
            'source': order.source,
            'order_status': order.orderStatus,
            'payment_status': order.paymentStatus,
            'is_takeaway': order.isTakeaway ? 1 : 0,
            'takeaway_notes': order.takeawayNotes,
            'created_at': order.createdAt.toIso8601String(),
            'version': order.version,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Insert items for this order
        for (final item in order.items) {
          await txn.insert(
            'queue_order_items',
            {
              'order_id': order.id,
              'name': item.name,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'notes': item.notes,
              'is_drink': item.isDrink ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Maintain recent_customers if table exists (v2 schema feature)
        try {
          await txn.insert(
            'recent_customers',
            {
              'id': 'cust-${order.customerName.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
              'name': order.customerName,
              'masked_phone': maskedPhone,
              'last_order_at': order.createdAt.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {
          // Ignore if running on v1 schema before migration
        }
      }

      // Record queue cache timestamp
      await txn.insert(
        'sync_metadata',
        {
          'key': metadataKeyLastCached,
          'value': timestamp,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Retrieves all cached orders along with their nested line items.
  Future<List<QueueOrder>> getOrders() async {
    final db = await _localDb.database;
    final orderRows = await db.query(
      'queue_orders',
      orderBy: 'created_at ASC',
    );

    final List<QueueOrder> result = [];

    for (final row in orderRows) {
      final orderId = row['id'] as String;
      final itemRows = await db.query(
        'queue_order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'id ASC',
      );

      final items = itemRows.map((i) => QueueOrderItem(
        name: i['name'] as String,
        quantity: i['quantity'] as int,
        unitPrice: i['unit_price'] as int,
        notes: i['notes'] as String?,
        isDrink: (i['is_drink'] as int) == 1,
      )).toList();

      result.add(
        QueueOrder(
          id: orderId,
          orderNumber: row['order_number'] as String,
          customerName: row['customer_name'] as String,
          customerPhone: row['customer_phone_masked'] as String,
          source: row['source'] as String,
          orderStatus: row['order_status'] as String,
          paymentStatus: row['payment_status'] as String,
          isTakeaway: (row['is_takeaway'] as int) == 1,
          takeawayNotes: row['takeaway_notes'] as String?,
          items: items,
          createdAt: DateTime.tryParse(row['created_at'] as String) ?? DateTime.now(),
          version: row['version'] as int? ?? 1,
        ),
      );
    }

    return result;
  }

  /// Updates status and version for a specific order.
  Future<void> updateOrderStatus(String id, String status, int newVersion) async {
    final db = await _localDb.database;
    await db.update(
      'queue_orders',
      {
        'order_status': status,
        'version': newVersion,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Loads cached queue snapshot with cache timestamp and stale marker.
  Future<CachedResult<List<QueueOrder>>> getOrdersWithFreshness({
    Duration staleThreshold = const Duration(minutes: 15),
  }) async {
    final orders = await getOrders();
    final lastCachedStr = await _localDb.getMetadata(metadataKeyLastCached);
    DateTime? cachedAt;
    if (lastCachedStr != null) {
      cachedAt = DateTime.tryParse(lastCachedStr);
    }

    final isStale = cachedAt == null ||
        DateTime.now().difference(cachedAt) > staleThreshold;

    return CachedResult<List<QueueOrder>>(
      data: orders,
      cachedAt: cachedAt,
      isStale: isStale,
    );
  }
}

