import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../queue/models/queue_order.dart';
import '../../settings/services/printer_service.dart';
import '../../settings/views/device_printer_view.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_status_badge.dart';

/// OrderSuccessDialog displays confirmation after an order is submitted,
/// and provides direct receipt printing and thermal printer integration.
/// Fulfills Issue #28 Criteria #5 (success state) & Printer integration.
class OrderSuccessDialog extends StatefulWidget {
  final QueueOrder order;
  final VoidCallback? onViewQueue;
  final VoidCallback? onNewOrder;

  const OrderSuccessDialog({
    super.key,
    required this.order,
    this.onViewQueue,
    this.onNewOrder,
  });

  static Future<void> show({
    required BuildContext context,
    required QueueOrder order,
    VoidCallback? onViewQueue,
    VoidCallback? onNewOrder,
  }) {
    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    if (isTablet) {
      return showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: OrderSuccessDialog(
                order: order,
                onViewQueue: () {
                  Navigator.of(ctx).pop();
                  if (onViewQueue != null) onViewQueue();
                },
                onNewOrder: () {
                  Navigator.of(ctx).pop();
                  if (onNewOrder != null) onNewOrder();
                },
              ),
            ),
          ),
        ),
      );
    } else {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
            ),
            child: SingleChildScrollView(
              child: OrderSuccessDialog(
                order: order,
                onViewQueue: () {
                  Navigator.of(ctx).pop();
                  if (onViewQueue != null) onViewQueue();
                },
                onNewOrder: () {
                  Navigator.of(ctx).pop();
                  if (onNewOrder != null) onNewOrder();
                },
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  State<OrderSuccessDialog> createState() => _OrderSuccessDialogState();
}

class _OrderSuccessDialogState extends State<OrderSuccessDialog> {
  bool _isPrinting = false;
  bool _printed = false;
  String? _printFeedback;

  @override
  void initState() {
    super.initState();
    if (PrinterService.instance.autoPrint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePrint();
      });
    }
  }

  Future<void> _handlePrint() async {
    if (_isPrinting) return;
    setState(() {
      _isPrinting = true;
      _printFeedback = null;
    });

    final success = await PrinterService.instance.printReceipt(widget.order);
    if (!mounted) return;

    setState(() {
      _isPrinting = false;
      _printed = success;
      _printFeedback = success
          ? 'Struk berhasil dikirim ke printer thermal (${PrinterService.instance.paperSize}).'
          : 'Gagal mencetak struk. Pastikan printer terhubung.';
    });
  }

  void _showReceiptPreview() {
    final receiptText = PrinterService.instance.formatReceipt(widget.order);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pratinjau Struk Thermal',
                      style: AppTypography.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Pengaturan Printer',
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DevicePrinterView(),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F9FB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      receiptText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Cetak Sekarang',
                icon: Icons.print_rounded,
                onPressed: () {
                  Navigator.pop(ctx);
                  _handlePrint();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Success Icon
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                color: AppColors.successBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 2. Title & Subtitle
          const Center(
            child: Text(
              'Pesanan Berhasil Dibuat!',
              style: AppTypography.headline,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              order.orderNumber,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Order Details Card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Kanal Sumber:',
                      style: AppTypography.labelSmall,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(child: AppStatusBadge.source(order.source)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pelanggan:', style: AppTypography.labelSmall),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        order.customerName,
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Layanan:', style: AppTypography.labelSmall),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        order.isTakeaway
                            ? 'Bungkus / Takeaway'
                            : 'Makan di Tempat',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: order.isTakeaway
                              ? AppColors.warning
                              : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:', style: AppTypography.titleMedium),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        CurrencyFormatter.formatRupiah(order.totalAmount),
                        style: AppTypography.titleLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 4. Print Section & Hardware Feedback
          AppButton(
            key: const Key('print-receipt-button'),
            label: _printed ? 'Cetak Ulang Struk' : 'Cetak Struk Nota',
            icon: Icons.print_rounded,
            variant: _printed ? AppButtonVariant.secondary : AppButtonVariant.primary,
            isLoading: _isPrinting,
            onPressed: _handlePrint,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: const Key('preview-receipt-button'),
                onPressed: _showReceiptPreview,
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text(
                  'Pratinjau Struk',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DevicePrinterView()),
                  );
                },
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text(
                  'Atur Printer',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_printFeedback != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                _printFeedback!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _printed ? AppColors.success : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),

          // 5. Final Order Actions
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Pesanan Baru',
                  variant: AppButtonVariant.secondary,
                  onPressed: widget.onNewOrder ?? () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Lihat di Antrean',
                  icon: Icons.list_alt_rounded,
                  onPressed: widget.onViewQueue ?? () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
