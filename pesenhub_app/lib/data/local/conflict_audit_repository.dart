import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../core/utils/pii_sanitizer.dart';
import 'local_database.dart';

/// Data model representing a recorded conflict resolution decision.
/// Fulfills Issue #34 Criteria #4 (conflict decisions recorded without sensitive PII).
class ConflictAuditEntry {
  final String id;
  final String orderId;
  final String? clientOrderId;
  final String conflictType;
  final String resolutionStrategy;
  final int clientVersion;
  final int serverVersion;
  final String resolvedPayloadJson;
  final String? notes;
  final DateTime createdAt;

  const ConflictAuditEntry({
    required this.id,
    required this.orderId,
    this.clientOrderId,
    required this.conflictType,
    required this.resolutionStrategy,
    required this.clientVersion,
    required this.serverVersion,
    required this.resolvedPayloadJson,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'client_order_id': clientOrderId,
      'conflict_type': conflictType,
      'resolution_strategy': resolutionStrategy,
      'client_version': clientVersion,
      'server_version': serverVersion,
      'resolved_payload_json': resolvedPayloadJson,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ConflictAuditEntry.fromMap(Map<String, dynamic> map) {
    return ConflictAuditEntry(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      clientOrderId: map['client_order_id'] as String?,
      conflictType: map['conflict_type'] as String,
      resolutionStrategy: map['resolution_strategy'] as String,
      clientVersion: (map['client_version'] as num).toInt(),
      serverVersion: (map['server_version'] as num).toInt(),
      resolvedPayloadJson: map['resolved_payload_json'] as String,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// Repository for persisting and querying conflict audit logs in SQLite.
class ConflictAuditRepository {
  final LocalDatabase localDb;

  ConflictAuditRepository({required this.localDb});

  /// Records a conflict decision into SQLite with strict PII sanitization.
  Future<void> logConflict({
    required String id,
    required String orderId,
    String? clientOrderId,
    required String conflictType,
    required String resolutionStrategy,
    required int clientVersion,
    required int serverVersion,
    required Map<String, dynamic> resolvedPayload,
    String? notes,
    DateTime? createdAt,
  }) async {
    final db = await localDb.database;

    // Sanitize any customer phone in payload
    final sanitizedPayload = Map<String, dynamic>.from(resolvedPayload);
    if (sanitizedPayload.containsKey('customer_phone')) {
      sanitizedPayload['customer_phone'] = PiiSanitizer.maskPhone(
        sanitizedPayload['customer_phone']?.toString(),
      );
    }

    final entry = ConflictAuditEntry(
      id: id,
      orderId: orderId,
      clientOrderId: clientOrderId,
      conflictType: conflictType,
      resolutionStrategy: resolutionStrategy,
      clientVersion: clientVersion,
      serverVersion: serverVersion,
      resolvedPayloadJson: jsonEncode(sanitizedPayload),
      notes: notes,
      createdAt: createdAt ?? DateTime.now(),
    );

    await db.insert(
      'conflict_logs',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all recorded conflict logs for a specific order.
  Future<List<ConflictAuditEntry>> getConflictLogsForOrder(
    String orderId,
  ) async {
    final db = await localDb.database;
    final rows = await db.query(
      'conflict_logs',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => ConflictAuditEntry.fromMap(r)).toList();
  }

  /// Retrieves all conflict logs across all orders.
  Future<List<ConflictAuditEntry>> getAllConflictLogs() async {
    final db = await localDb.database;
    final rows = await db.query('conflict_logs', orderBy: 'created_at DESC');
    return rows.map((r) => ConflictAuditEntry.fromMap(r)).toList();
  }

  /// Returns count of recorded conflicts.
  Future<int> countConflicts() async {
    final db = await localDb.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM conflict_logs',
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }
}
