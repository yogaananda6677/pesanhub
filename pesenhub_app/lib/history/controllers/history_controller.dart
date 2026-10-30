import 'package:flutter/material.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../queue/models/queue_order.dart';

enum HistoryStatusFilter {
  all('Semua'),
  completed('Selesai'),
  cancelled('Batal');

  final String label;
  const HistoryStatusFilter(this.label);
}

enum HistoryDateRangeFilter {
  today('Hari Ini'),
  yesterday('Kemarin'),
  last7Days('7 Hari'),
  last30Days('30 Hari'),
  custom('Kustom');

  final String label;
  const HistoryDateRangeFilter(this.label);
}

class HistoryController extends ChangeNotifier {
  final PesenHubApiClient? apiClient;
  final String? branchId;
  final List<QueueOrder>? initialOrders;

  bool _isLoading = false;
  String? _errorMessage;
  List<QueueOrder> _orders = [];
  String _searchQuery = '';
  HistoryStatusFilter _statusFilter = HistoryStatusFilter.all;
  HistoryDateRangeFilter _dateRangeFilter = HistoryDateRangeFilter.today;
  DateTimeRange? _customDateRange;

  HistoryController({this.apiClient, this.branchId, this.initialOrders}) {
    if (initialOrders != null) {
      _orders = List.of(initialOrders!);
    }
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<QueueOrder> get orders => List.unmodifiable(_orders);
  String get searchQuery => _searchQuery;
  HistoryStatusFilter get statusFilter => _statusFilter;
  HistoryDateRangeFilter get dateRangeFilter => _dateRangeFilter;
  DateTimeRange? get customDateRange => _customDateRange;

  /// Returns filtered and sorted orders based on active filters and search query.
  List<QueueOrder> get filteredOrders {
    var result = _orders.where((order) {
      // Status filter
      if (_statusFilter == HistoryStatusFilter.completed &&
          !order.isCompleted) {
        return false;
      }
      if (_statusFilter == HistoryStatusFilter.cancelled &&
          !order.isCancelled) {
        return false;
      }

      // Search query filter
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final matchesOrderNum = order.orderNumber.toLowerCase().contains(query);
        final matchesCustomer = order.customerName.toLowerCase().contains(
          query,
        );
        final matchesPhone = order.customerPhone.toLowerCase().contains(query);
        final matchesId = order.id.toLowerCase().contains(query);
        final matchesItems = order.items.any(
          (item) => item.name.toLowerCase().contains(query),
        );

        if (!matchesOrderNum &&
            !matchesCustomer &&
            !matchesPhone &&
            !matchesId &&
            !matchesItems) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort newest first
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(HistoryStatusFilter filter) {
    _statusFilter = filter;
    notifyListeners();
  }

  Future<void> setDateRangeFilter(
    HistoryDateRangeFilter filter, {
    DateTimeRange? customRange,
  }) async {
    _dateRangeFilter = filter;
    if (filter == HistoryDateRangeFilter.custom) {
      _customDateRange = customRange;
    }
    notifyListeners();
    await loadOrders();
  }

  (DateTime?, DateTime?) _calculateDateBounds() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_dateRangeFilter) {
      case HistoryDateRangeFilter.today:
        return (todayStart, todayEnd);
      case HistoryDateRangeFilter.yesterday:
        final yesterdayStart = todayStart.subtract(const Duration(days: 1));
        final yesterdayEnd = DateTime(
          yesterdayStart.year,
          yesterdayStart.month,
          yesterdayStart.day,
          23,
          59,
          59,
        );
        return (yesterdayStart, yesterdayEnd);
      case HistoryDateRangeFilter.last7Days:
        return (todayStart.subtract(const Duration(days: 6)), todayEnd);
      case HistoryDateRangeFilter.last30Days:
        return (todayStart.subtract(const Duration(days: 29)), todayEnd);
      case HistoryDateRangeFilter.custom:
        if (_customDateRange != null) {
          final start = DateTime(
            _customDateRange!.start.year,
            _customDateRange!.start.month,
            _customDateRange!.start.day,
          );
          final end = DateTime(
            _customDateRange!.end.year,
            _customDateRange!.end.month,
            _customDateRange!.end.day,
            23,
            59,
            59,
          );
          return (start, end);
        }
        return (null, null);
    }
  }

  Future<void> loadOrders() async {
    if (apiClient == null) {
      if (initialOrders != null) {
        _orders = List.of(initialOrders!);
      }
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final (from, to) = _calculateDateBounds();
      final fetched = await apiClient!.fetchOrders(
        branchId: branchId,
        createdFrom: from,
        createdTo: to,
        order: 'desc',
        pageSize: 100,
      );

      _orders = fetched;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Gagal memuat riwayat transaksi: $e';
      notifyListeners();
    }
  }

  Future<void> refresh() => loadOrders();
}
