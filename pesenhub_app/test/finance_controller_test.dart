import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/finance/controllers/finance_controller.dart';
import 'package:pesenhub_app/finance/models/financial_summary.dart';
import 'package:pesenhub_app/finance/models/top_products.dart';

class MockFinanceRemoteGateway implements FinanceRemoteGateway {
  FinancialSummary? mockSummary;
  TopProductsResponse? mockTopProducts;
  bool shouldThrow = false;
  DateTime? lastFrom;
  DateTime? lastTo;
  String? lastBranchId;

  @override
  Future<FinancialSummary> fetchFinancialSummary({
    String? branchId,
    DateTime? from,
    DateTime? to,
    bool includeBranches = false,
  }) async {
    lastFrom = from;
    lastTo = to;
    lastBranchId = branchId;
    if (shouldThrow) {
      throw Exception('Network connection failed');
    }
    return mockSummary ??
        const FinancialSummary(
          grossRevenue: 1500000,
          totalDiscount: 50000,
          netRevenue: 1450000,
          cashRevenue: 900000,
          digitalRevenue: 550000,
          revenueByChannel: {'CASHIER_MANUAL': 1000000, 'WHATSAPP': 450000},
          ordersByChannel: {'CASHIER_MANUAL': 20, 'WHATSAPP': 5},
          totalCompletedOrders: 25,
        );
  }

  @override
  Future<TopProductsResponse> fetchTopProducts({
    String? branchId,
    DateTime? from,
    DateTime? to,
    int limit = 5,
  }) async {
    if (shouldThrow) {
      throw Exception('Network connection failed');
    }
    return mockTopProducts ??
        const TopProductsResponse(
          topMenus: [
            TopProduct(
              name: 'Martabak Manis',
              quantitySold: 30,
              totalSales: 750000,
            ),
            TopProduct(
              name: 'Terang Bulan',
              quantitySold: 15,
              totalSales: 300000,
            ),
          ],
          topToppings: [
            TopProduct(
              name: 'Keju Cheddar',
              quantitySold: 20,
              totalSales: 100000,
            ),
          ],
        );
  }
}

void main() {
  group('FinanceController Unit Tests', () {
    late MockFinanceRemoteGateway mockGateway;
    late FinanceController controller;

    setUp(() {
      mockGateway = MockFinanceRemoteGateway();
      controller = FinanceController(
        gateway: mockGateway,
        branchId: 'branch-001',
      );
    });

    test('initial state is configured with today filter and no error', () {
      expect(controller.selectedPeriod, equals(FinancePeriod.today));
      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.summary, isNull);
      expect(controller.topProducts, isNull);
    });

    test('loadData successfully updates summary and top products', () async {
      await controller.loadData();

      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.summary, isNotNull);
      expect(controller.summary!.netRevenue, equals(1450000));
      expect(controller.summary!.grossRevenue, equals(1500000));
      expect(controller.summary!.cashRevenue, equals(900000));
      expect(controller.summary!.digitalRevenue, equals(550000));
      expect(controller.topProducts, isNotNull);
      expect(controller.topProducts!.topMenus.length, equals(2));
      expect(mockGateway.lastBranchId, equals('branch-001'));
    });

    test('loadData handles failure gracefully with errorMessage', () async {
      mockGateway.shouldThrow = true;

      await controller.loadData();

      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, contains('Network connection failed'));
    });

    test('setPeriod switches to yesterday and sends formatted dates', () async {
      await controller.setPeriod(FinancePeriod.yesterday);

      expect(controller.selectedPeriod, equals(FinancePeriod.yesterday));
      expect(mockGateway.lastFrom, isNotNull);
      expect(mockGateway.lastTo, isNotNull);
    });

    test('setPeriod switches to thisWeek and thisMonth', () async {
      await controller.setPeriod(FinancePeriod.thisWeek);
      expect(controller.selectedPeriod, equals(FinancePeriod.thisWeek));

      await controller.setPeriod(FinancePeriod.thisMonth);
      expect(controller.selectedPeriod, equals(FinancePeriod.thisMonth));
    });

    test('setCustomRange sets custom period and reloads data', () async {
      final start = DateTime(2026, 10, 1);
      final end = DateTime(2026, 10, 15);

      await controller.setCustomRange(start, end);

      expect(controller.selectedPeriod, equals(FinancePeriod.custom));
      expect(controller.customStartDate, equals(start));
      expect(controller.customEndDate, equals(end));
      expect(mockGateway.lastFrom, equals(start));
      expect(mockGateway.lastTo, equals(end));
    });

    test('refresh invokes loadData', () async {
      await controller.refresh();
      expect(controller.summary, isNotNull);
    });
  });
}
