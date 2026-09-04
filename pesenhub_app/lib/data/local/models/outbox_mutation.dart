/// OutboxSyncStatus defines the lifecycle states of an offline mutation.
enum OutboxSyncStatus {
  pending,
  syncing,
  synced,
  failedTransient,
  failedPermanent;

  String toDbString() {
    switch (this) {
      case OutboxSyncStatus.pending:
        return 'PENDING';
      case OutboxSyncStatus.syncing:
        return 'SYNCING';
      case OutboxSyncStatus.synced:
        return 'SYNCED';
      case OutboxSyncStatus.failedTransient:
        return 'FAILED_TRANSIENT';
      case OutboxSyncStatus.failedPermanent:
        return 'FAILED_PERMANENT';
    }
  }

  static OutboxSyncStatus fromDbString(String str) {
    switch (str.toUpperCase()) {
      case 'SYNCING':
        return OutboxSyncStatus.syncing;
      case 'SYNCED':
        return OutboxSyncStatus.synced;
      case 'FAILED_TRANSIENT':
        return OutboxSyncStatus.failedTransient;
      case 'FAILED_PERMANENT':
        return OutboxSyncStatus.failedPermanent;
      case 'PENDING':
      default:
        return OutboxSyncStatus.pending;
    }
  }
}

/// OutboxMutation represents an offline action queued for reliable background sync.
/// Fulfills Issue #33 Acceptance Criteria #1, #2, #3, and #4.
class OutboxMutation {
  final String id;
  final String idempotencyKey;
  final String clientOrderId;
  final String mutationType; // CREATE_ORDER, UPDATE_STATUS, UPDATE_AVAILABILITY
  final String payloadJson;
  final OutboxSyncStatus syncStatus;
  final int retryCount;
  final DateTime? lastAttemptedAt;
  final DateTime? nextRetryAt;
  final String? serverOrderId;
  final String? errorMessage;
  final DateTime createdAt;

  const OutboxMutation({
    required this.id,
    required this.idempotencyKey,
    required this.clientOrderId,
    this.mutationType = 'CREATE_ORDER',
    required this.payloadJson,
    this.syncStatus = OutboxSyncStatus.pending,
    this.retryCount = 0,
    this.lastAttemptedAt,
    this.nextRetryAt,
    this.serverOrderId,
    this.errorMessage,
    required this.createdAt,
  });

  /// True if the mutation is ready for processing.
  bool isReadyForSync(DateTime now) {
    if (syncStatus == OutboxSyncStatus.synced ||
        syncStatus == OutboxSyncStatus.failedPermanent) {
      return false;
    }
    if (syncStatus == OutboxSyncStatus.syncing) {
      return false;
    }
    if (nextRetryAt != null && now.isBefore(nextRetryAt!)) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'idempotency_key': idempotencyKey,
      'client_order_id': clientOrderId,
      'mutation_type': mutationType,
      'payload_json': payloadJson,
      'sync_status': syncStatus.toDbString(),
      'retry_count': retryCount,
      'last_attempted_at': lastAttemptedAt?.toIso8601String(),
      'next_retry_at': nextRetryAt?.toIso8601String(),
      'server_order_id': serverOrderId,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory OutboxMutation.fromMap(Map<String, dynamic> map) {
    return OutboxMutation(
      id: map['id'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      clientOrderId: map['client_order_id'] as String,
      mutationType: map['mutation_type'] as String? ?? 'CREATE_ORDER',
      payloadJson: map['payload_json'] as String,
      syncStatus: OutboxSyncStatus.fromDbString(map['sync_status'] as String),
      retryCount: map['retry_count'] as int? ?? 0,
      lastAttemptedAt: map['last_attempted_at'] != null
          ? DateTime.tryParse(map['last_attempted_at'] as String)
          : null,
      nextRetryAt: map['next_retry_at'] != null
          ? DateTime.tryParse(map['next_retry_at'] as String)
          : null,
      serverOrderId: map['server_order_id'] as String?,
      errorMessage: map['error_message'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String) ?? DateTime.now(),
    );
  }

  OutboxMutation copyWith({
    String? id,
    String? idempotencyKey,
    String? clientOrderId,
    String? mutationType,
    String? payloadJson,
    OutboxSyncStatus? syncStatus,
    int? retryCount,
    DateTime? lastAttemptedAt,
    DateTime? nextRetryAt,
    String? serverOrderId,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return OutboxMutation(
      id: id ?? this.id,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      clientOrderId: clientOrderId ?? this.clientOrderId,
      mutationType: mutationType ?? this.mutationType,
      payloadJson: payloadJson ?? this.payloadJson,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      serverOrderId: serverOrderId ?? this.serverOrderId,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
