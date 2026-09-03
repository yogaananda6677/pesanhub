import 'package:flutter/material.dart';
import '../../queue/models/queue_order.dart';

/// KdsController manages the state, deterministic prioritization,
/// and 1-tap status transitions for kitchen display tickets.
/// Fulfills Issue #30 Criteria #1, #2, and #4.
class KdsController extends ChangeNotifier {
  final Map<String, QueueOrder> _ordersMap = {};
  String _statusFilter = 'ALL'; // 'ALL', 'ACCEPTED', 'PREPARING'
  final Set<String> _processingOrderIds = {};
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _timeOverride;

  KdsController({List<QueueOrder>? initialOrders}) {
    if (initialOrders != null) {
      setSnapshot(initialOrders);
    }
  }

  DateTime get now => _timeOverride ?? DateTime.now();

  set timeOverride(DateTime? override) {
    _timeOverride = override;
    notifyListeners();
  }

  String get statusFilter => _statusFilter;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Set<String> get processingOrderIds => _processingOrderIds;

  bool isOrderProcessing(String orderId) =>
      _processingOrderIds.contains(orderId);

  void setStatusFilter(String filter) {
    if (_statusFilter == filter) return;
    _statusFilter = filter;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Sets or updates the kitchen orders snapshot.
  /// Deduplicates by order.id idempotently.
  void setSnapshot(List<QueueOrder> orders) {
    _ordersMap.clear();
    for (final order in orders) {
      // Only include active kitchen orders (ACCEPTED or PREPARING)
      if (order.orderStatus == 'ACCEPTED' || order.orderStatus == 'PREPARING') {
        _ordersMap[order.id] = order;
      }
    }
    _errorMessage = null;
    notifyListeners();
  }

  /// Ingests a single order update or adds a new kitchen order.
  void upsertOrder(QueueOrder order) {
    if (order.orderStatus == 'ACCEPTED' || order.orderStatus == 'PREPARING') {
      _ordersMap[order.id] = order;
    } else {
      // Completed, ready for pickup, or cancelled orders leave the kitchen display
      _ordersMap.remove(order.id);
    }
    notifyListeners();
  }

  /// Counts of active kitchen orders by status.
  int countForStatus(String status) {
    if (status == 'ALL') {
      return _ordersMap.length;
    }
    return _ordersMap.values.where((o) => o.orderStatus == status).length;
  }

  /// Criteria #2: Deterministic sorting where overdue (> 15m) orders appear first,
  /// followed by FIFO based on creation time.
  List<QueueOrder> get sortedOrders {
    final list = _ordersMap.values.toList();
    list.sort((a, b) {
      final aOverdue = a.isOverdueAt(now);
      final bOverdue = b.isOverdueAt(now);

      // 1. Overdue orders come first
      if (aOverdue && !bOverdue) return -1;
      if (!aOverdue && bOverdue) return 1;

      // 2. FIFO by createdAt ascending
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// Filtered kitchen orders based on current statusFilter.
  List<QueueOrder> get filteredOrders {
    final list = sortedOrders;
    if (_statusFilter == 'ALL') {
      return list;
    }
    return list.where((o) => o.orderStatus == _statusFilter).toList();
  }

  /// Criteria #4: 1-Tap status transition with version contract and double-action prevention.
  Future<bool> executeQuickAction(
    QueueOrder order, {
    Future<QueueOrder> Function(
      String orderId,
      String targetStatus,
      int expectedVersion,
    )?
    transitionFn,
  }) async {
    if (_processingOrderIds.contains(order.id)) {
      return false; // Double-action guard
    }

    String? targetStatus;
    if (order.orderStatus == 'ACCEPTED') {
      targetStatus = 'PREPARING'; // "Mulai Masak"
    } else if (order.orderStatus == 'PREPARING') {
      targetStatus = 'READY_FOR_PICKUP'; // "Tandai Siap"
    } else {
      return false;
    }

    _processingOrderIds.add(order.id);
    notifyListeners();

    try {
      if (transitionFn != null) {
        final updated = await transitionFn(
          order.id,
          targetStatus,
          order.version,
        );
        upsertOrder(updated);
      } else {
        final updated = QueueOrder(
          id: order.id,
          orderNumber: order.orderNumber,
          customerName: order.customerName,
          customerPhone: order.customerPhone,
          source: order.source,
          orderStatus: targetStatus,
          paymentStatus: order.paymentStatus,
          isTakeaway: order.isTakeaway,
          takeawayNotes: order.takeawayNotes,
          items: order.items,
          createdAt: order.createdAt,
          version: order.version + 1,
        );
        upsertOrder(updated);
      }
      _processingOrderIds.remove(order.id);
      notifyListeners();
      return true;
    } catch (e) {
      _processingOrderIds.remove(order.id);
      _errorMessage = 'Gagal memperbarui status tiket: $e';
      notifyListeners();
      return false;
    }
  }
}
