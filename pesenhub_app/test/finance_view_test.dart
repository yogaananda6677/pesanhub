import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/finance/controllers/cash_shift_controller.dart';
import 'package:pesenhub_app/finance/controllers/finance_controller.dart';
import 'package:pesenhub_app/finance/models/cash_shift.dart';
import 'package:pesenhub_app/finance/models/financial_summary.dart';
import 'package:pesenhub_app/finance/models/top_products.dart';
import 'package:pesenhub_app/finance/views/finance_view.dart';

class FakeFinanceGateway implements FinanceRemoteGateway {
  final FinancialSummary summary;
  final TopProductsResponse topProducts;

  FakeFinanceGateway({required this.summary, required this.topProducts});

  @override
  Future<FinancialSummary> fetchFinancialSummary({
    String? branchId,
    DateTime? from,
    DateTime? to,
    bool includeBranches = false,
  }) async => summary;

  @override
  Future<TopProductsResponse> fetchTopProducts({
    String? branchId,
    DateTime? from,
    DateTime? to,
    int limit = 5,
  }) async => topProducts;
}

class FakeShiftGateway implements ShiftRemoteGateway {
  CashShift? currentShift;
  List<CashShift> history;

  FakeShiftGateway({this.currentShift, List<CashShift>? history})
    : history = history ?? [];

  @override
  Future<CashShift?> fetchCurrentShift({String? branchId}) async =>
      currentShift;

  @override
  Future<CashShift> openShift({
    required int startingCash,
    String? notes,
    String? branchId,
  }) async {
    final shift = CashShift(
      id: 'shift-new',
      branchId: branchId ?? 'b1',
      cashierId: 'cashier-1',
      cashierName: 'Ahmad Kasir',
      shiftStart: DateTime.now(),
      startingCash: startingCash,
      status: 'OPEN',
      notes: notes,
    );
    currentShift = shift;
    return shift;
  }

  @override
  Future<CashShift> closeShift({
    String? shiftId,
    required int actualCash,
    String? notes,
  }) async {
    final s = currentShift!;
    final closed = s.copyWith(
      shiftEnd: DateTime.now(),
      actualCash: actualCash,
      discrepancy: actualCash - s.expectedCash,
      status: 'CLOSED',
      notes: notes,
    );
    currentShift = null;
    history.insert(0, closed);
    return closed;
  }

  @override
  Future<List<CashShift>> fetchShiftHistory({
    String? branchId,
    int limit = 20,
  }) async => history;
}

void main() {
  group('FinanceView Widget Tests', () {
    late FakeFinanceGateway financeGateway;
    late FakeShiftGateway shiftGateway;
    late FinanceController financeController;
    late CashShiftController cashShiftController;

    setUp(() {
      financeGateway = FakeFinanceGateway(
        summary: const FinancialSummary(
          grossRevenue: 2000000,
          totalDiscount: 100000,
          netRevenue: 1900000,
          cashRevenue: 1200000,
          digitalRevenue: 700000,
          revenueByChannel: {'CASHIER_MANUAL': 1400000, 'WHATSAPP': 500000},
          ordersByChannel: {'CASHIER_MANUAL': 25, 'WHATSAPP': 10},
          totalCompletedOrders: 35,
        ),
        topProducts: const TopProductsResponse(
          topMenus: [
            TopProduct(
              name: 'Martabak Telur Spesial',
              quantitySold: 20,
              totalSales: 700000,
            ),
            TopProduct(
              name: 'Terang Bulan Coklat Keju',
              quantitySold: 15,
              totalSales: 450000,
            ),
          ],
          topToppings: [
            TopProduct(
              name: 'Keju Mozzarella',
              quantitySold: 18,
              totalSales: 90000,
            ),
          ],
        ),
      );

      shiftGateway = FakeShiftGateway();

      financeController = FinanceController(
        gateway: financeGateway,
        branchId: 'b1',
      );
      cashShiftController = CashShiftController(
        gateway: shiftGateway,
        branchId: 'b1',
      );
    });

    Widget createWidget({Size surfaceSize = const Size(1200, 900)}) {
      return MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(size: surfaceSize),
            child: FinanceView(
              financeController: financeController,
              cashShiftController: cashShiftController,
              branchId: 'b1',
            ),
          ),
        ),
      );
    }

    testWidgets(
      'renders filter chips, financial stats, and inactive shift card',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Check Filter Chips
        expect(find.text('Hari Ini'), findsOneWidget);
        expect(find.text('Kemarin'), findsOneWidget);
        expect(find.text('Minggu Ini'), findsOneWidget);
        expect(find.text('Bulan Ini'), findsOneWidget);
        expect(find.text('Kustom'), findsOneWidget);

        // Check Summary Cards
        expect(find.text('TOTAL OMSET BERSIH'), findsOneWidget);
        expect(find.text('Rp 1.900.000'), findsOneWidget);
        expect(find.text('Omset Kotor'), findsOneWidget);
        expect(find.text('Rp 2.000.000'), findsOneWidget);
        expect(find.text('Total Diskon'), findsOneWidget);
        expect(find.text('Rp 100.000'), findsOneWidget);
        expect(find.text('Pesanan Sukses'), findsOneWidget);
        expect(find.text('35'), findsOneWidget);

        // Check Payment Breakdown
        expect(find.text('Breakdown Metode Pembayaran'), findsOneWidget);
        expect(find.text('Tunai (Cash)'), findsOneWidget);
        expect(find.text('Non-Tunai (QRIS)'), findsOneWidget);

        // Check Channel Breakdown
        expect(find.text('Distribusi Kanal Penjualan'), findsOneWidget);
        expect(find.text('Kasir POS Manual'), findsOneWidget);
        expect(find.text('WhatsApp Hermes'), findsOneWidget);

        // Check Top Products
        expect(find.text('Paling Diminati'), findsOneWidget);
        expect(find.text('Martabak Telur Spesial'), findsOneWidget);

        // Switch to Topping tab
        await tester.tap(find.byKey(const Key('top-toppings-tab')));
        await tester.pumpAndSettle();
        expect(find.text('Keju Mozzarella'), findsOneWidget);

        // Inactive shift status
        expect(find.text('Kas Laci Kasir (Cash Register)'), findsOneWidget);
        expect(find.text('Belum ada shift kasir yang aktif'), findsOneWidget);
        expect(find.byKey(const Key('open-shift-button')), findsOneWidget);
      },
    );

    testWidgets(
      'displays active shift details and triggers close cashier dialog',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));

        shiftGateway.currentShift = CashShift(
          id: 'shift-active-1',
          branchId: 'b1',
          cashierId: 'c1',
          cashierName: 'Budi Santoso',
          shiftStart: DateTime.now().subtract(const Duration(hours: 4)),
          startingCash: 200000,
          expectedCash: 850000,
          cashIn: 650000,
          status: 'OPEN',
        );

        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        expect(find.text('Bertugas: Budi Santoso'), findsOneWidget);
        expect(find.text('Rp 200.000'), findsOneWidget); // modal awal
        expect(find.text('Rp 650.000'), findsOneWidget); // penjualan tunai
        expect(find.text('Rp 850.000'), findsOneWidget); // estimasi kas

        // Action button "Tutup Kasir & Rekonsiliasi Kas"
        final closeBtn = find.byKey(const Key('close-shift-button'));
        expect(closeBtn, findsOneWidget);

        // Tap Tutup Kasir
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // Dialog should appear
        expect(find.text('Ekspektasi Kas di Laci'), findsOneWidget);
        expect(
          find.text('Total Uang Fisik Aktual di Laci (Rp)'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('confirm-close-shift-button')),
          findsOneWidget,
        );
      },
    );

    testWidgets('can open cash shift from empty state dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final openBtn = find.byKey(const Key('open-shift-button'));
      await tester.tap(openBtn);
      await tester.pumpAndSettle();

      // Open shift dialog
      expect(find.text('Modal Awal Kasir (Rp)'), findsOneWidget);

      final input = find.byKey(const Key('starting-cash-input'));
      await tester.enterText(input, '150000');
      await tester.pumpAndSettle();

      final submitBtn = find.text('Buka Shift');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Shift is now open
      expect(shiftGateway.currentShift, isNotNull);
      expect(shiftGateway.currentShift!.startingCash, equals(150000));
    });
  });
}
