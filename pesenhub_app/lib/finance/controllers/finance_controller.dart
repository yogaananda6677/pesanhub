import 'package:flutter/material.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../models/financial_summary.dart';
import '../models/top_products.dart';

enum FinancePeriodFilter { today, yesterday, thisWeek, thisMonth, custom }

typedef FinancePeriod = FinancePeriodFilter;

extension FinancePeriodFilterExt on FinancePeriodFilter {
  String get label {
    switch (this) {
      case FinancePeriodFilter.today:
        return 'Hari Ini';
      case FinancePeriodFilter.yesterday:
        return 'Kemarin';
      case FinancePeriodFilter.thisWeek:
        return 'Minggu Ini';
      case FinancePeriodFilter.thisMonth:
        return 'Bulan Ini';
      case FinancePeriodFilter.custom:
        return 'Kustom';
    }
  }
}

class FinanceController extends ChangeNotifier {
  final FinanceRemoteGateway gateway;
  final String? branchId;

  FinancePeriodFilter _filter = FinancePeriodFilter.today;
  DateTimeRange? _customRange;
  FinancialSummary? _summary;
  TopProductsResponse? _topProducts;
  bool _isLoading = false;
  String? _errorMessage;

  FinanceController({required this.gateway, this.branchId});

  FinancePeriodFilter get filter => _filter;
  FinancePeriodFilter get selectedPeriod => _filter;
  DateTimeRange? get customRange => _customRange;
  DateTime? get customStartDate => _customRange?.start;
  DateTime? get customEndDate => _customRange?.end;
  FinancialSummary? get summary => _summary;
  TopProductsResponse? get topProducts => _topProducts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  DateTimeRange get effectiveDateRange {
    final now = DateTime.now();
    switch (_filter) {
      case FinancePeriodFilter.today:
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case FinancePeriodFilter.yesterday:
        final y = now.subtract(const Duration(days: 1));
        final start = DateTime(y.year, y.month, y.day);
        final end = DateTime(y.year, y.month, y.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case FinancePeriodFilter.thisWeek:
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case FinancePeriodFilter.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case FinancePeriodFilter.custom:
        return _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
            );
    }
  }

  Future<void> setFilter(
    FinancePeriodFilter newFilter, [
    DateTimeRange? customRange,
  ]) async {
    _filter = newFilter;
    if (newFilter == FinancePeriodFilter.custom && customRange != null) {
      _customRange = customRange;
    }
    await loadData();
  }

  Future<void> setPeriod(
    FinancePeriodFilter period, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    DateTimeRange? range;
    if (startDate != null && endDate != null) {
      range = DateTimeRange(start: startDate, end: endDate);
    }
    await setFilter(period, range);
  }

  Future<void> setCustomRange(DateTime start, DateTime end) async {
    await setFilter(
      FinancePeriodFilter.custom,
      DateTimeRange(start: start, end: end),
    );
  }

  Future<void> refresh() => loadData(silent: true);

  Future<void> loadData({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final range = effectiveDateRange;
      final summaryFuture = gateway.fetchFinancialSummary(
        branchId: branchId,
        from: range.start,
        to: range.end,
      );
      final topProductsFuture = gateway.fetchTopProducts(
        branchId: branchId,
        from: range.start,
        to: range.end,
        limit: 5,
      );

      final results = await Future.wait([summaryFuture, topProductsFuture]);
      _summary = results[0] as FinancialSummary;
      _topProducts = results[1] as TopProductsResponse;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Gagal memuat data keuangan: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
