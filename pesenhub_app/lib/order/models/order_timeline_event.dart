/// Representation of a discrete order lifecycle event or milestone.
/// Fulfills Issue #34 Criteria #2 (deduplication of order timeline events).
class OrderTimelineEvent {
  final String id;
  final String orderId;
  final String status;
  final String actor;
  final DateTime timestamp;
  final int version;
  final String? notes;

  const OrderTimelineEvent({
    required this.id,
    required this.orderId,
    required this.status,
    required this.actor,
    required this.timestamp,
    required this.version,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'status': status,
      'actor': actor,
      'timestamp': timestamp.toIso8601String(),
      'version': version,
      'notes': notes,
    };
  }

  factory OrderTimelineEvent.fromJson(Map<String, dynamic> json) {
    return OrderTimelineEvent(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      status: json['status'] as String,
      actor: json['actor'] as String? ?? 'STAFF',
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: (json['version'] as num?)?.toInt() ?? 1,
      notes: json['notes'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderTimelineEvent &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Deduplicates a list of raw timeline events.
  /// Eliminates duplicate event IDs and repeated same-status transitions,
  /// sorting chronologically by timestamp and version.
  static List<OrderTimelineEvent> deduplicate(
    List<OrderTimelineEvent> rawEvents,
  ) {
    final seenIds = <String>{};
    final seenStatusTimestamps = <String>{};
    final result = <OrderTimelineEvent>[];

    // Sort chronologically first
    final sorted = List<OrderTimelineEvent>.from(rawEvents)
      ..sort((a, b) {
        final timeComp = a.timestamp.compareTo(b.timestamp);
        if (timeComp != 0) return timeComp;
        return a.version.compareTo(b.version);
      });

    for (final event in sorted) {
      // Check duplicate ID
      if (seenIds.contains(event.id)) {
        continue;
      }

      // Check duplicate status milestone (e.g. two PREPARING at same version or time)
      final statusKey = '${event.orderId}_${event.status}_${event.version}';
      if (seenStatusTimestamps.contains(statusKey)) {
        continue;
      }

      seenIds.add(event.id);
      seenStatusTimestamps.add(statusKey);
      result.add(event);
    }

    return result;
  }
}
