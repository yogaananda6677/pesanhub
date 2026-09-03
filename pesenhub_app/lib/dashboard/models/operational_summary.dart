/// OperationalSummary holds a consistent snapshot of cashier operational metrics.
/// Fulfills Issue #25 Acceptance Criteria #1 and #2.
class OperationalSummary {
  final int pendingCount;
  final int preparingCount;
  final int readyCount;
  final int overdueCount;
  final int completedCount;
  final int pendingSyncCount;
  final DateTime lastUpdatedAt;
  final bool isStale;
  final bool isOffline;

  const OperationalSummary({
    this.pendingCount = 0,
    this.preparingCount = 0,
    this.readyCount = 0,
    this.overdueCount = 0,
    this.completedCount = 0,
    this.pendingSyncCount = 0,
    required this.lastUpdatedAt,
    this.isStale = false,
    this.isOffline = false,
  });

  /// Total count of orders actively requiring cashier or kitchen attention.
  int get activeOrdersCount => pendingCount + preparingCount + readyCount;

  /// True if there are any active orders or unsynced offline mutations.
  bool get hasActiveOperations => activeOrdersCount > 0 || pendingSyncCount > 0;

  /// Human-readable time representation (HH:mm) for freshness indication.
  String get formattedTime {
    final hour = lastUpdatedAt.hour.toString().padLeft(2, '0');
    final minute = lastUpdatedAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  OperationalSummary copyWith({
    int? pendingCount,
    int? preparingCount,
    int? readyCount,
    int overdueCount = 0,
    int? completedCount,
    int? pendingSyncCount,
    DateTime? lastUpdatedAt,
    bool? isStale,
    bool? isOffline,
  }) {
    return OperationalSummary(
      pendingCount: pendingCount ?? this.pendingCount,
      preparingCount: preparingCount ?? this.preparingCount,
      readyCount: readyCount ?? this.readyCount,
      overdueCount: overdueCount != 0 ? overdueCount : this.overdueCount,
      completedCount: completedCount ?? this.completedCount,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      isStale: isStale ?? this.isStale,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}
