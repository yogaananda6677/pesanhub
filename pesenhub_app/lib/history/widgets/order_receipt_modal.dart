import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../queue/models/queue_order.dart';
import '../../settings/services/printer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class OrderReceiptModal extends StatefulWidget {
  final QueueOrder order;
  final PrinterService? printerService;

  const OrderReceiptModal({
    super.key,
    required this.order,
    this.printerService,
  });

  static Future<void> show(
    BuildContext context, {
    required QueueOrder order,
    PrinterService? printerService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          OrderReceiptModal(order: order, printerService: printerService),
    );
  }

  @override
  State<OrderReceiptModal> createState() => _OrderReceiptModalState();
}

class _OrderReceiptModalState extends State<OrderReceiptModal> {
  bool _isPrinting = false;

  PrinterService get _printer =>
      widget.printerService ?? PrinterService.instance;

  Future<void> _handlePrint() async {
    setState(() => _isPrinting = true);
    final success = await _printer.printReceipt(widget.order);
    if (!mounted) return;
    setState(() => _isPrinting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Struk pesanan #${widget.order.orderNumber} berhasil dicetak ulang.',
          ),
          backgroundColor: AppColors.accentGreenDeep,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gagal mencetak: Printer thermal Bluetooth tidak terhubung.',
          ),
          backgroundColor: AppColors.accentRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isCancelled = order.isCancelled;
    final isCompleted = order.isCompleted;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                order.orderNumber,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isCancelled
                                      ? AppColors.accentRedBg
                                      : (isCompleted
                                            ? AppColors.accentGreenBg
                                            : AppColors.accentAmberBg),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isCancelled
                                        ? AppColors.accentRedBorder
                                        : (isCompleted
                                              ? AppColors.accentGreenBorder
                                              : AppColors.accentAmber),
                                  ),
                                ),
                                child: Text(
                                  isCancelled
                                      ? 'DIBATALKAN'
                                      : (isCompleted
                                            ? 'SELESAI'
                                            : order.orderStatus),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isCancelled
                                        ? AppColors.accentRed
                                        : (isCompleted
                                              ? AppColors.accentGreenDeep
                                              : AppColors.slateDark),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            order.formattedDateTime,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.neutralTextLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      color: AppColors.slate,
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border, height: 1),

              // Scrollable Details
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    // Cancellation Banner
                    if (isCancelled)
                      Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.accentRedBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accentRedBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.accentRed,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pesanan Dibatalkan',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AppColors.accentRed,
                                    ),
                                  ),
                                  if (order.cancellationReason != null &&
                                      order.cancellationReason!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      'Alasan: ${order.cancellationReason}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                  if (order.cancelledBy != null &&
                                      order.cancelledBy!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Dibatalkan oleh: ${order.cancelledBy}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.neutralText,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Customer & Service Info Card
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.warmSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                size: 16,
                                color: AppColors.slate,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                order.customerName.isEmpty
                                    ? 'Pelanggan Umum'
                                    : order.customerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (order.customerPhone.isNotEmpty) ...[
                                const Text(
                                  ' • ',
                                  style: TextStyle(color: AppColors.slateLight),
                                ),
                                Text(
                                  order.customerPhone,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.neutralText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.storefront_rounded,
                                size: 16,
                                color: AppColors.slate,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                order.diningOptionLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (order.branchName != null &&
                                  order.branchName!.isNotEmpty) ...[
                                const Text(
                                  ' • ',
                                  style: TextStyle(color: AppColors.slateLight),
                                ),
                                Text(
                                  order.branchName!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.neutralText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (order.takeawayNotes != null &&
                              order.takeawayNotes!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.notes_rounded,
                                  size: 16,
                                  color: AppColors.slate,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Catatan: ${order.takeawayNotes}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.neutralText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Items Header
                    const Text(
                      'Rincian Pesanan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Items List
                    for (final item in order.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.quantity}x',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (item.notes != null &&
                                      item.notes!.isNotEmpty)
                                    Text(
                                      item.notes!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.neutralTextLight,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              CurrencyFormatter.formatRupiah(item.subtotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(color: AppColors.border, height: 24),

                    // Summary Calculations
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Subtotal',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.neutralText,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatRupiah(order.subtotal),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if ((order.discountAmount ?? 0) > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            order.discountName != null &&
                                    order.discountName!.isNotEmpty
                                ? 'Diskon (${order.discountName})'
                                : 'Diskon Promo',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.accentGreenDeep,
                            ),
                          ),
                          Text(
                            '-${CurrencyFormatter.formatRupiah(order.discountAmount!)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accentGreenDeep,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Pembayaran',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatRupiah(order.totalAmount),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Payment method pill
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Metode & Status',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.neutralTextLight,
                          ),
                        ),
                        Text(
                          '${order.paymentMethod ?? "Tunai"} • ${order.paymentStatus == "PAID" ? "Lunas" : order.paymentStatus}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: order.paymentStatus == 'PAID'
                                ? AppColors.accentGreenDeep
                                : AppColors.slate,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Bottom Action Button: Reprint
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      key: const Key('reprint-receipt-button'),
                      onPressed: _isPrinting ? null : _handlePrint,
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.print_rounded, size: 20),
                      label: Text(
                        _isPrinting ? 'Mencetak Struk...' : 'Cetak Ulang Struk',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
