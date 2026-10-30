import 'package:flutter/material.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../settings/services/printer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../controllers/cash_shift_controller.dart';
import '../controllers/finance_controller.dart';
import '../models/cash_shift.dart';
import '../models/financial_summary.dart';
import '../models/top_products.dart';
import '../widgets/cash_reconciliation_dialog.dart';
import '../widgets/cash_shift_card.dart';
import '../widgets/channel_breakdown_card.dart';
import '../widgets/payment_breakdown_card.dart';
import '../widgets/print_daily_recap_dialog.dart';
import '../widgets/revenue_stat_cards.dart';
import '../widgets/top_selling_products_card.dart';

class FinanceView extends StatefulWidget {
  final PesenHubApiClient? apiClient;
  final String? branchId;
  final FinanceController? financeController;
  final CashShiftController? cashShiftController;
  final PrinterService? printerService;
  final VoidCallback? onRefresh;

  const FinanceView({
    super.key,
    this.apiClient,
    this.branchId,
    this.financeController,
    this.cashShiftController,
    this.printerService,
    this.onRefresh,
  });

  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView> {
  late final FinanceController _financeController;
  late final CashShiftController _cashShiftController;
  bool _initializedInternally = false;

  @override
  void initState() {
    super.initState();
    if (widget.financeController != null) {
      _financeController = widget.financeController!;
    } else if (widget.apiClient != null) {
      _financeController = FinanceController(
        gateway: widget.apiClient!,
        branchId: widget.branchId,
      );
      _initializedInternally = true;
    } else {
      _financeController = FinanceController(
        gateway: _FallbackFinanceGateway(),
        branchId: widget.branchId,
      );
      _initializedInternally = true;
    }

    if (widget.cashShiftController != null) {
      _cashShiftController = widget.cashShiftController!;
    } else if (widget.apiClient != null) {
      _cashShiftController = CashShiftController(
        gateway: widget.apiClient!,
        branchId: widget.branchId,
      );
    } else {
      _cashShiftController = CashShiftController(
        gateway: _FallbackShiftGateway(),
        branchId: widget.branchId,
      );
    }

    _financeController.addListener(_onStateChanged);
    _cashShiftController.addListener(_onStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _financeController.loadData();
      _cashShiftController.loadCurrentShift();
    });
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _financeController.removeListener(_onStateChanged);
    _cashShiftController.removeListener(_onStateChanged);
    if (_initializedInternally) {
      _financeController.dispose();
      _cashShiftController.dispose();
    }
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    await Future.wait([
      _financeController.loadData(),
      _cashShiftController.loadCurrentShift(),
    ]);
    widget.onRefresh?.call();
  }

  void _showOpenShiftModal() {
    final startCashController = TextEditingController(text: '100000');
    final notesController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.lock_open_rounded,
                          color: AppColors.accentGreen,
                          size: 22,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Buka Shift Kasir Baru',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Masukkan modal awal uang fisik di dalam laci kasir.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Modal Awal Kasir (Rp)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('starting-cash-input'),
                      controller: startCashController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixText: 'Rp ',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Catatan (Opsional)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('open-shift-notes-input'),
                      controller: notesController,
                      decoration: InputDecoration(
                        hintText: 'Contoh: Modal pecahan kecil...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogCtx, false),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Batal'),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              key: const Key('submit-open-shift-button'),
                              onPressed: () async {
                                final cleaned = startCashController.text
                                    .replaceAll(RegExp(r'[^0-9]'), '');
                                final cash = int.tryParse(cleaned) ?? 0;
                                final success = await _cashShiftController
                                    .openShift(
                                      startingCash: cash,
                                      notes: notesController.text.trim(),
                                    );
                                if (success && mounted) {
                                  navigator.pop(true);
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Shift kasir baru berhasil dibuka!',
                                      ),
                                      backgroundColor: AppColors.accentGreen,
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Buka Shift',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCloseShiftModal() {
    final active = _cashShiftController.activeShift;
    if (active == null) return;

    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => CashReconciliationDialog(
        activeShift: active,
        onConfirmClose: (actualCash, notes) async {
          final closed = await _cashShiftController.closeShift(
            actualCash: actualCash,
            notes: notes,
          );
          if (closed != null && mounted) {
            _showPrintRecapModal(closed);
          }
        },
      ),
    );
  }

  void _showPrintRecapModal(CashShift shift) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => PrintDailyRecapDialog(
        shift: shift,
        summary: _financeController.summary,
        printerService: widget.printerService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _financeController.summary ?? FinancialSummary.empty();
    final topProducts =
        _financeController.topProducts ?? TopProductsResponse.empty();

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.terracotta,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= AppSpacing.tabletBreakpoint;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? AppSpacing.xl : AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick Date Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: FinancePeriodFilter.values.map((f) {
                      final isSelected = _financeController.filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: FilterChip(
                          key: Key('finance-filter-${f.name}'),
                          label: Text(f.label),
                          selected: isSelected,
                          onSelected: (_) async {
                            if (f == FinancePeriodFilter.custom) {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2024),
                                lastDate: DateTime.now(),
                                initialDateRange:
                                    _financeController.effectiveDateRange,
                              );
                              if (picked != null) {
                                await _financeController.setFilter(f, picked);
                              }
                            } else {
                              await _financeController.setFilter(f);
                            }
                          },
                          selectedColor: AppColors.terracottaSoft,
                          checkmarkColor: AppColors.terracotta,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.terracotta
                                : AppColors.textSecondary,
                          ),
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.terracotta
                                  : AppColors.outlineVariant,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Error Banner
                if (_financeController.errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _financeController.errorMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _financeController.loadData,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),

                // Cash Register / Shift Card
                CashShiftCard(
                  activeShift: _cashShiftController.activeShift,
                  onOpenShift: _showOpenShiftModal,
                  onCloseShift: _showCloseShiftModal,
                ),
                const SizedBox(height: AppSpacing.md),

                // Revenue Stat Cards
                RevenueStatCards(summary: summary),
                const SizedBox(height: AppSpacing.md),

                // Multi-column or stacked analytics
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            PaymentBreakdownCard(summary: summary),
                            const SizedBox(height: AppSpacing.md),
                            ChannelBreakdownCard(summary: summary),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 4,
                        child: TopSellingProductsCard(topProducts: topProducts),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      PaymentBreakdownCard(summary: summary),
                      const SizedBox(height: AppSpacing.md),
                      ChannelBreakdownCard(summary: summary),
                      const SizedBox(height: AppSpacing.md),
                      TopSellingProductsCard(topProducts: topProducts),
                    ],
                  ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FallbackFinanceGateway implements FinanceRemoteGateway {
  @override
  Future<FinancialSummary> fetchFinancialSummary({
    String? branchId,
    DateTime? from,
    DateTime? to,
    bool includeBranches = false,
  }) async {
    return FinancialSummary.empty();
  }

  @override
  Future<TopProductsResponse> fetchTopProducts({
    String? branchId,
    DateTime? from,
    DateTime? to,
    int limit = 5,
  }) async {
    return TopProductsResponse.empty();
  }
}

class _FallbackShiftGateway implements ShiftRemoteGateway {
  @override
  Future<CashShift?> fetchCurrentShift({String? branchId}) async => null;

  @override
  Future<CashShift> openShift({
    required int startingCash,
    String? notes,
    String? branchId,
  }) async {
    final now = DateTime.now();
    return CashShift(
      id: 'mock-shift-1',
      branchId: branchId ?? 'mock-branch',
      cashierId: 'mock-cashier',
      cashierName: 'Kasir Utama',
      shiftStart: now,
      startingCash: startingCash,
      expectedCash: startingCash,
      cashIn: 0,
      cashOut: 0,
      status: 'OPEN',
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<CashShift> closeShift({
    String? shiftId,
    required int actualCash,
    String? notes,
  }) async {
    final now = DateTime.now();
    return CashShift(
      id: shiftId ?? 'mock-shift-1',
      branchId: 'mock-branch',
      cashierId: 'mock-cashier',
      cashierName: 'Kasir Utama',
      shiftStart: now.subtract(const Duration(hours: 4)),
      shiftEnd: now,
      startingCash: 100000,
      expectedCash: 100000,
      actualCash: actualCash,
      cashIn: 0,
      cashOut: 0,
      discrepancy: actualCash - 100000,
      notes: notes,
      status: 'CLOSED',
      createdAt: now.subtract(const Duration(hours: 4)),
      updatedAt: now,
    );
  }

  @override
  Future<List<CashShift>> fetchShiftHistory({
    String? branchId,
    int limit = 20,
  }) async {
    return [];
  }
}
