import 'package:flutter/material.dart';
import '../../core/utils/event_deduplicator.dart';
import '../../data/local/conflict_audit_repository.dart';
import '../../order/models/order_conflict.dart';
import '../models/queue_order.dart';
import '../models/queue_state.dart';

/// QueueController manages unified order queue collection, deduplication, filtering, and stable sorting.
/// Fulfills Issue #26 & #34 Acceptance Criteria (deduplication, server-wins protection, conflict resolution).
class QueueController extends ChangeNotifier {
  final Map<String, QueueOrder> _ordersMap = {};
  final EventDeduplicator _deduplicator = EventDeduplicator();
  DateTime? _timeOverride;

  QueueState _state = const QueueState.loading();
  String _statusFilter = 'ALL';
  String _sourceFilter = 'ALL';
  String _searchQuery = '';

  QueueController({List<QueueOrder>? initialOrders, DateTime? timeOverride}) {
    _timeOverride = timeOverride;
    if (initialOrders != null) {
      setSnapshot(initialOrders);
    }
  }

  // Getters
  QueueState get state => _state;
  String get statusFilter => _statusFilter;
  String get sourceFilter => _sourceFilter;
  String get searchQuery => _searchQuery;
  DateTime get now => _timeOverride ?? DateTime.now();

  set timeOverride(DateTime? time) {
    _timeOverride = time;
    notifyListeners();
  }

  /// All unique orders without filtering.
  List<QueueOrder> get allOrders => _ordersMap.values.toList();

  /// Total count of orders in queue map.
  int get totalCount => _ordersMap.length;

  /// Count of orders with a given status.
  int countForStatus(String status) {
    if (status == 'ALL') {
      return _ordersMap.values.where((o) => o.isActive).length;
    }
    return _ordersMap.values.where((o) => o.orderStatus == status).length;
  }

  /// Count of active orders exceeding the 15-minute preparation threshold.
  int get overdueCount =>
      _ordersMap.values.where((o) => o.isOverdueAt(now)).length;

  /// Ingests a full server snapshot (e.g. on initial load or recovery reconnect).
  /// Replaces collection idempotently without creating duplicates.
  void setSnapshot(
    List<QueueOrder> orders, {
    bool isStale = false,
    bool isOffline = false,
  }) {
    _ordersMap.clear();
    for (final order in orders) {
      _ordersMap[order.id] = order;
    }

    if (_ordersMap.isEmpty) {
      _state = QueueState.empty(isStale: isStale, isOffline: isOffline);
    } else {
      _state = QueueState.success(isStale: isStale, isOffline: isOffline);
    }
    notifyListeners();
  }

  EventDeduplicator get deduplicator => _deduplicator;

  /// Ingests a single order event (e.g. from WebSocket or local mutation).
  /// Fulfills Issue #34 Criteria #1 (server-wins) and #2 (duplicate prevention).
  void upsertOrder(QueueOrder order, {String? eventId}) {
    if (eventId != null && !_deduplicator.shouldProcess(eventId)) {
      // Event ID already processed (Criteria #2)
      return;
    }

    final existing = _ordersMap[order.id];
    if (existing != null) {
      if (order.version < existing.version) {
        // Ignore older out-of-order event
        return;
      }

      // Server-wins protection (Criteria #1): terminal states and paid status cannot be regressed
      const finalStatuses = {'COMPLETED', 'CANCELLED', 'REJECTED'};
      if (finalStatuses.contains(existing.orderStatus) &&
          !finalStatuses.contains(order.orderStatus)) {
        return;
      }
      if (existing.paymentStatus == 'PAID' && order.paymentStatus != 'PAID') {
        return;
      }

      // Duplicate event check: if version and core fields are identical, avoid unnecessary notifyListeners
      if (order.version == existing.version &&
          order.orderStatus == existing.orderStatus &&
          order.paymentStatus == existing.paymentStatus &&
          order.takeawayNotes == existing.takeawayNotes) {
        return;
      }
    }

    _ordersMap[order.id] = order;
    if (_state.status == QueueStatus.empty ||
        _state.status == QueueStatus.loading) {
      _state = const QueueState.success();
    }
    notifyListeners();
  }

  /// Updates status of an existing order locally with version bump.
  /// Returns false if prevented by server-wins terminal state guard.
  bool updateOrderStatus(String orderId, String newStatus) {
    final existing = _ordersMap[orderId];
    if (existing == null) return false;

    // Server-wins protection: cannot modify already terminal orders
    const finalStatuses = {'COMPLETED', 'CANCELLED', 'REJECTED'};
    if (finalStatuses.contains(existing.orderStatus)) {
      return false;
    }

    _ordersMap[orderId] = existing.copyWith(
      orderStatus: newStatus,
      version: existing.version + 1,
    );
    notifyListeners();
    return true;
  }

  /// Applies a conflict resolution decision deterministically and logs audit trail.
  /// Fulfills Criteria #3 & #4.
  Future<QueueOrder> applyConflictResolution({
    required ConflictClassification classification,
    required ResolutionStrategy strategy,
    ConflictAuditRepository? auditRepo,
  }) async {
    final resolved = ConflictResolver.resolve(
      classification: classification,
      strategy: strategy,
    );

    _ordersMap[resolved.id] = resolved;
    notifyListeners();

    if (auditRepo != null) {
      try {
        await auditRepo.logConflict(
          id: 'conf-${DateTime.now().millisecondsSinceEpoch}',
          orderId: resolved.id,
          clientOrderId: classification.localOrder.id,
          conflictType: classification.type.name,
          resolutionStrategy: strategy.name,
          clientVersion: classification.localOrder.version,
          serverVersion: classification.serverOrder.version,
          resolvedPayload: {
            'order_status': resolved.orderStatus,
            'payment_status': resolved.paymentStatus,
            'takeaway_notes': resolved.takeawayNotes,
            'version': resolved.version,
          },
          notes: classification.reason,
        );
      } catch (_) {}
    }

    return resolved;
  }

  /// Sets presentation error state.
  void setError(String message) {
    _state = QueueState.error(message);
    notifyListeners();
  }

  /// Sets presentation loading state.
  void setLoading() {
    _state = const QueueState.loading();
    notifyListeners();
  }

  // Filter setters
  void setStatusFilter(String status) {
    if (_statusFilter != status) {
      _statusFilter = status;
      notifyListeners();
    }
  }

  void setSourceFilter(String source) {
    if (_sourceFilter != source) {
      _sourceFilter = source;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery != query) {
      _searchQuery = query;
      notifyListeners();
    }
  }

  /// Filtered, searched, and stably sorted order list.
  /// Fulfills Acceptance Criteria #4: Stable sorting.
  List<QueueOrder> get filteredOrders {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = _ordersMap.values.where((order) {
      // 1. Status filter
      if (_statusFilter == 'ALL') {
        if (!order.isActive) return false;
      } else if (order.orderStatus != _statusFilter) {
        return false;
      }

      // 2. Source filter
      if (_sourceFilter != 'ALL' && order.source != _sourceFilter) {
        return false;
      }

      // 3. Search query
      if (query.isNotEmpty) {
        final matchesNumber = order.orderNumber.toLowerCase().contains(query);
        final matchesName = order.customerName.toLowerCase().contains(query);
        if (!matchesNumber && !matchesName) return false;
      }

      return true;
    }).toList();

    // Stable sort:
    // 1. Overdue orders first
    // 2. Status rank: PENDING (0) -> ACCEPTED (1) -> PREPARING (2) -> READY_FOR_PICKUP (3) -> others (4)
    // 3. FIFO: createdAt ascending
    filtered.sort((a, b) {
      final aOverdue = a.isOverdueAt(now);
      final bOverdue = b.isOverdueAt(now);

      if (aOverdue && !bOverdue) return -1;
      if (!aOverdue && bOverdue) return 1;

      final rankA = _statusRank(a.orderStatus);
      final rankB = _statusRank(b.orderStatus);
      if (rankA != rankB) {
        return rankA.compareTo(rankB);
      }

      return a.createdAt.compareTo(b.createdAt);
    });

    return filtered;
  }

  int _statusRank(String status) {
    switch (status) {
      case 'PENDING':
        return 0;
      case 'ACCEPTED':
        return 1;
      case 'PREPARING':
        return 2;
      case 'READY_FOR_PICKUP':
        return 3;
      default:
        return 4;
    }
  }
}
