import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/cash_shift.dart';

class CashReconciliationDialog extends StatefulWidget {
  final CashShift activeShift;
  final Future<void> Function(int actualCash, String? notes) onConfirmClose;

  const CashReconciliationDialog({
    super.key,
    required this.activeShift,
    required this.onConfirmClose,
  });

  @override
  State<CashReconciliationDialog> createState() =>
      _CashReconciliationDialogState();
}

class _CashReconciliationDialogState extends State<CashReconciliationDialog> {
  final _cashController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  int get _enteredCash {
    final cleaned = _cashController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  int get _discrepancy => _enteredCash - widget.activeShift.expectedCash;

  @override
  void dispose() {
    _cashController.disposeWidget();
    _notesController.disposeWidget();
    super.dispose();
  }

  Future<void> _submit() async {
    final cash = _enteredCash;
    if (cash < 0) {
      setState(() => _error = 'Nominal kas tidak boleh bernilai negatif.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await widget.onConfirmClose(cash, _notesController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal menutup kasir: $e';
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final discrepancy = _discrepancy;
    final hasDiscrepancy = discrepancy != 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.terracottaSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calculate_rounded,
                      color: AppColors.terracotta,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tutup Kasir & Rekonsiliasi Kas',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Hitung uang fisik di laci dan audit selisih',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // System Overview Table
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWarm,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    _buildRow(
                      'Modal Awal',
                      widget.activeShift.formattedStartingCash,
                    ),
                    const SizedBox(height: 6),
                    _buildRow(
                      'Penerimaan Tunai Masuk',
                      widget.activeShift.formattedCashIn,
                      isPositive: true,
                    ),
                    if (widget.activeShift.cashOut > 0) ...[
                      const SizedBox(height: 6),
                      _buildRow(
                        'Pengeluaran Kas Laci',
                        widget.activeShift.formattedCashOut,
                        isNegative: true,
                      ),
                    ],
                    const Divider(height: 16, color: AppColors.outlineVariant),
                    _buildRow(
                      'Ekspektasi Kas di Laci',
                      widget.activeShift.formattedExpectedCash,
                      isBold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Input Actual Cash
              const Text(
                'Total Uang Fisik Aktual di Laci (Rp)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('actual-cash-input'),
                controller: _cashController,
                keyboardType: TextInputType.number,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Contoh: 350000',
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
              const SizedBox(height: AppSpacing.sm),

              // Discrepancy Indicator
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: hasDiscrepancy
                      ? (discrepancy > 0
                            ? AppColors.accentBlueBg
                            : AppColors.errorBg)
                      : AppColors.accentGreenBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasDiscrepancy
                        ? (discrepancy > 0
                              ? AppColors.accentBlue
                              : AppColors.error)
                        : AppColors.accentGreen,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasDiscrepancy
                          ? (discrepancy > 0
                                ? Icons.info_outline_rounded
                                : Icons.warning_amber_rounded)
                          : Icons.check_circle_outline_rounded,
                      size: 20,
                      color: hasDiscrepancy
                          ? (discrepancy > 0
                                ? AppColors.accentBlue
                                : AppColors.error)
                          : AppColors.accentGreen,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            !hasDiscrepancy
                                ? 'Status: Kas Fisik Sesuai (Pas)'
                                : (discrepancy > 0
                                      ? 'Status: Kas Lebih'
                                      : 'Status: Kas Kurang (Selisih)'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: hasDiscrepancy
                                  ? (discrepancy > 0
                                        ? AppColors.accentBlue
                                        : AppColors.error)
                                  : AppColors.accentGreen,
                            ),
                          ),
                          Text(
                            !hasDiscrepancy
                                ? 'Uang fisik di laci sama persis dengan ekspektasi.'
                                : 'Selisih: ${CurrencyFormatter.formatRupiah(discrepancy.abs())}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Notes
              const Text(
                'Catatan Rekonsiliasi (Opsional)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('reconciliation-notes-input'),
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Contoh: Uang lebih tip dari pelanggan...',
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

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        key: const Key('cancel-reconciliation-button'),
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.pop(context),
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
                        key: const Key('confirm-close-shift-button'),
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.terracotta,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Konfirmasi Tutup Kasir',
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
  }

  Widget _buildRow(
    String label,
    String value, {
    bool isPositive = false,
    bool isNegative = false,
    bool isBold = false,
  }) {
    Color valColor = AppColors.textPrimary;
    if (isPositive) valColor = AppColors.accentGreen;
    if (isNegative) valColor = AppColors.error;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 14 : 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: valColor,
          ),
        ),
      ],
    );
  }
}

extension on TextEditingController {
  void disposeWidget() {
    dispose();
  }
}
