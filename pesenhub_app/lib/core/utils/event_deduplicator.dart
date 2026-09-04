import 'dart:collection';

/// EventDeduplicator provides bounded in-memory deduplication of network events,
/// WebSocket payloads, and sync acknowledgments.
/// Fulfills Issue #34 Acceptance Criteria #2.
class EventDeduplicator {
  final int maxCapacity;
  final LinkedHashSet<String> _seenEventIds = LinkedHashSet<String>();

  EventDeduplicator({this.maxCapacity = 500});

  /// Checks if an event has already been processed.
  /// If not seen, records the event and returns true (should process).
  /// If already seen, returns false (duplicate event, skip).
  bool shouldProcess(String eventId) {
    final key = eventId.trim();
    if (key.isEmpty) return true;

    if (_seenEventIds.contains(key)) {
      return false; // Duplicate
    }

    _seenEventIds.add(key);

    // Evict oldest entries if capacity exceeded
    if (_seenEventIds.length > maxCapacity) {
      _seenEventIds.remove(_seenEventIds.first);
    }

    return true;
  }

  /// Explicitly marks an event key as processed without checking.
  void markProcessed(String eventId) {
    final key = eventId.trim();
    if (key.isEmpty) return;
    _seenEventIds.add(key);
    if (_seenEventIds.length > maxCapacity) {
      _seenEventIds.remove(_seenEventIds.first);
    }
  }

  /// Checks if an event has already been recorded.
  bool isDuplicate(String eventId) {
    final key = eventId.trim();
    if (key.isEmpty) return false;
    return _seenEventIds.contains(key);
  }

  /// Current number of tracked events.
  int get size => _seenEventIds.length;

  /// Clears the deduplication cache.
  void clear() {
    _seenEventIds.clear();
  }
}
