/// CachedResult wraps cached entities with freshness metadata and stale marker.
/// Fulfills Issue #32 Acceptance Criteria #2.
class CachedResult<T> {
  final T data;
  final DateTime? cachedAt;
  final bool isStale;

  const CachedResult({required this.data, this.cachedAt, this.isStale = false});

  /// Time elapsed since the data was cached in local database.
  Duration get age {
    if (cachedAt == null) return Duration.zero;
    return DateTime.now().difference(cachedAt!);
  }

  /// Formatted time string (HH:mm) when cache was stored.
  String get formattedCachedAt {
    if (cachedAt == null) return '-';
    final hour = cachedAt!.hour.toString().padLeft(2, '0');
    final minute = cachedAt!.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  CachedResult<T> copyWith({T? data, DateTime? cachedAt, bool? isStale}) {
    return CachedResult<T>(
      data: data ?? this.data,
      cachedAt: cachedAt ?? this.cachedAt,
      isStale: isStale ?? this.isStale,
    );
  }
}
