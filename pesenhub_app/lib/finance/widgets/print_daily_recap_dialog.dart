import 'package:flutter/material.dart';
import '../../settings/services/printer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/cash_shift.dart';
import '../models/financial_summary.dart';

class PrintDailyRecapDialog extends StatefulWidget {
  final CashShift shift;
  final FinancialSummary? summary;
  final PrinterService? printerService;

  const PrintDailyRecapDialog({
    super.key,
    required this.shift,
    this.summary,
    this.printerService,
  });

  @override
  State<PrintDailyRecapDialog> createState() => _PrintDailyRecapDialogState();
}

class _PrintDailyRecapDialogState extends State<PrintDailyRecapDialog> {
  bool _isPrinting = false;

  PrinterService get _printer =>
      widget.printerService ?? PrinterService.instance;

  Future<void> _print() async {
    setState(() => _isPrinting = true);
    final success = await _printer.printShiftClosingReport(
      widget.shift,
      widget.summary,
    );
    if (!mounted) return;
    setState(() => _isPrinting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Laporan tutup kasir berhasil dikirim ke printer thermal (${_printer.paperSize}).'
              : 'Gagal mencetak: Printer thermal tidak terhubung.',
        ),
        backgroundColor: success ? AppColors.accentGreen : AppColors.error,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reportText = _printer.formatShiftClosingReport(
      widget.shift,
      widget.summary,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
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
                      Icons.print_rounded,
                      color: AppColors.terracotta,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pratinjau Struk Rekap Shift',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Format cetak thermal ESC/POS 58mm/80mm',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Tutup',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Monospaced receipt preview container
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF7F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      reportText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF2C2420),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        key: const Key('close-recap-dialog-button'),
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Tutup'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        key: const Key('print-shift-report-button'),
                        onPressed: _isPrinting ? null : _print,
                        icon: _isPrinting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.print_rounded, size: 18),
                        label: Text(
                          _isPrinting
                              ? 'Mencetak...'
                              : 'Cetak ke Printer Thermal',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.terracotta,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
}
