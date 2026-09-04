import 'package:sqflite/sqflite.dart';
import 'local_database.dart';
import 'models/outbox_mutation.dart';

/// OutboxRepository manages durable, SQLite-persisted offline mutations.
/// Fulfills Issue #33 Acceptance Criteria #1, #2, #3, and #4.
class OutboxRepository {
  final LocalDatabase _localDb;

  OutboxRepository(this._localDb);

  /// Enqueues a new offline mutation to the durable SQLite store.
  Future<void> enqueueMutation(OutboxMutation mutation) async {
    final db = await _localDb.database;
    await db.insert(
      'outbox_mutations',
      mutation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves mutations ready for synchronization in strict FIFO order.
  Future<List<OutboxMutation>> getPendingMutations({DateTime? asOf}) async {
    final db = await _localDb.database;
    final nowIso = (asOf ?? DateTime.now()).toIso8601String();

    final rows = await db.query(
      'outbox_mutations',
      where:
          "(sync_status = 'PENDING' OR sync_status = 'FAILED_TRANSIENT') "
          "AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [nowIso],
      orderBy: 'created_at ASC',
    );

    return rows.map((r) => OutboxMutation.fromMap(r)).toList();
  }

  /// Retrieves all recorded mutations regardless of status.
  Future<List<OutboxMutation>> getAllMutations() async {
    final db = await _localDb.database;
    final rows = await db.query('outbox_mutations', orderBy: 'created_at ASC');
    return rows.map((r) => OutboxMutation.fromMap(r)).toList();
  }

  /// Finds a mutation by local client order ID.
  Future<OutboxMutation?> getByClientOrderId(String clientOrderId) async {
    final db = await _localDb.database;
    final rows = await db.query(
      'outbox_mutations',
      where: 'client_order_id = ?',
      whereArgs: [clientOrderId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OutboxMutation.fromMap(rows.first);
  }

  /// Marks mutation as actively being processed over the network.
  Future<void> markSyncing(String id) async {
    final db = await _localDb.database;
    await db.update(
      'outbox_mutations',
      {
        'sync_status': OutboxSyncStatus.syncing.toDbString(),
        'last_attempted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks mutation as successfully acknowledged by the backend server.
  Future<void> markSynced(String id, {required String serverOrderId}) async {
    final db = await _localDb.database;
    await db.update(
      'outbox_mutations',
      {
        'sync_status': OutboxSyncStatus.synced.toDbString(),
        'server_order_id': serverOrderId,
        'error_message': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records transient failure (e.g. network dropout, 5xx) with calculated backoff.
  Future<void> markTransientFailure(
    String id, {
    required String error,
    required Duration backoff,
  }) async {
    final db = await _localDb.database;
    final now = DateTime.now();
    final nextRetry = now.add(backoff);

    final currentRows = await db.query(
      'outbox_mutations',
      columns: ['retry_count'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final currentRetry = currentRows.isNotEmpty
        ? (currentRows.first['retry_count'] as int? ?? 0)
        : 0;

    await db.update(
      'outbox_mutations',
      {
        'sync_status': OutboxSyncStatus.failedTransient.toDbString(),
        'retry_count': currentRetry + 1,
        'last_attempted_at': now.toIso8601String(),
        'next_retry_at': nextRetry.toIso8601String(),
        'error_message': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records permanent validation failure (e.g. 400 Bad Request, unprocessable).
  /// Stops automatic retry.
  Future<void> markPermanentFailure(String id, {required String error}) async {
    final db = await _localDb.database;
    await db.update(
      'outbox_mutations',
      {
        'sync_status': OutboxSyncStatus.failedPermanent.toDbString(),
        'next_retry_at': null,
        'error_message': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Counts mutations that are still pending or failed.
  Future<int> getPendingCount() async {
    final db = await _localDb.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM outbox_mutations WHERE sync_status != 'SYNCED'",
      ),
    );
    return result ?? 0;
  }

  /// Counts permanent validation errors requiring user attention.
  Future<int> getPermanentFailureCount() async {
    final db = await _localDb.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM outbox_mutations WHERE sync_status = 'FAILED_PERMANENT'",
      ),
    );
    return result ?? 0;
  }

  /// Deletes a specific mutation by ID.
  Future<void> deleteMutation(String id) async {
    final db = await _localDb.database;
    await db.delete('outbox_mutations', where: 'id = ?', whereArgs: [id]);
  }

  /// Purges all successfully synced mutations.
  Future<void> clearSyncedMutations() async {
    final db = await _localDb.database;
    await db.delete('outbox_mutations', where: "sync_status = 'SYNCED'");
  }
}
