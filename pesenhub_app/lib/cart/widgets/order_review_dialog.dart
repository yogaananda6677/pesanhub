import 'package:flutter/material.dart';
import '../../queue/models/queue_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/app_status_badge.dart';
import '../controllers/cart_controller.dart';
import '../models/cart_order_draft.dart';

import 'package:flutter/services.dart';

/// OrderReviewDialog provides an explicit pre-submission review of the cashier's order.
/// Fulfills Issue #28 Criteria #1, #2, #3, and #4.
class OrderReviewDialog extends StatefulWidget {
  final CartController controller;
  final Future<QueueOrder> Function(CartOrderDraft draft)? submitFn;
  final ValueChanged<QueueOrder>? onOrderCreated;

  const OrderReviewDialog({
    super.key,
    required this.controller,
    this.submitFn,
    this.onOrderCreated,
  });

  /// Helper to display this dialog responsively across mobile and tablet.
  static Future<QueueOrder?> show({
    required BuildContext context,
    required CartController controller,
    Future<QueueOrder> Function(CartOrderDraft draft)? submitFn,
  }) {
    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    if (isTablet) {
      return showDialog<QueueOrder>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 780),
            child: OrderReviewDialog(
              controller: controller,
              submitFn: submitFn,
              onOrderCreated: (order) => Navigator.of(ctx).pop(order),
            ),
          ),
        ),
      );
    } else {
      return showModalBottomSheet<QueueOrder>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
            ),
            child: OrderReviewDialog(
              controller: controller,
              submitFn: submitFn,
              onOrderCreated: (order) => Navigator.of(ctx).pop(order),
            ),
          ),
        ),
      );
    }
  }

  @override
  State<OrderReviewDialog> createState() => _OrderReviewDialogState();
}

class _OrderReviewDialogState extends State<OrderReviewDialog> {
  bool _payNow = true;
  int _paymentMethodIndex = 0; // 0: Tunai, 1: Non-Tunai
  final TextEditingController _cashInputController = TextEditingController();
  int _receivedAmount = 0;

  @override
  void initState() {
    super.initState();
    _receivedAmount = widget.controller.totalAmount;
    _cashInputController.text = _receivedAmount.toString();
  }

  @override
  void dispose() {
    _cashInputController.dispose();
    super.dispose();
  }

  void _onCashInputChanged(String val) {
    final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(clean) ?? 0;
    setState(() {
      _receivedAmount = num;
    });
  }

  void _selectCashPreset(int amount) {
    setState(() {
      _receivedAmount = amount;
      _cashInputController.text = amount.toString();
    });
  }

  String _formatRupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp ${buffer.toString()}';
  }

  Widget _buildPresetChip(String label, int amount) {
    final isSelected = _receivedAmount == amount;
    return InkWell(
      onTap: () => _selectCashPreset(amount),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final draft = widget.controller.currentDraft;
        final bool isSubmitting = widget.controller.isSubmitting;
        final String? errorMsg = widget.controller.errorMessage;
        final String? discrepancyMsg = widget.controller.discrepancyMessage;
        final isCash = _paymentMethodIndex == 0;
        final isCashValid = _receivedAmount >= draft.totalAmount;
        final change = _receivedAmount - draft.totalAmount;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Dialog Header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Review Pesanan Kasir',
                          style: AppTypography.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppStatusBadge.source('CASHIER_MANUAL'),
                            Text(
                              '${draft.totalItemCount} item',
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 2. Scrollable Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Criteria #3: Discrepancy warning banner
                    if (discrepancyMsg != null) ...[
                      AppBanner(
                        message: discrepancyMsg,
                        type: AppBannerType.warning,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Error banner
                    if (errorMsg != null) ...[
                      AppBanner(message: errorMsg, type: AppBannerType.error),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Customer & Takeaway Summary Card
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Pelanggan:',
                                style: AppTypography.labelSmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                child: Text(
                                  draft.customerName,
                                  style: AppTypography.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (draft.customerPhone != null &&
                              draft.customerPhone!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'WhatsApp:',
                                  style: AppTypography.labelSmall,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    draft.customerPhone!,
                                    style: AppTypography.bodyMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Sumber Transaksi:',
                                style: AppTypography.labelSmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                child: AppStatusBadge.source(draft.source),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              ChoiceChip(
                                label: const Text('Kasir'),
                                avatar: const Icon(Icons.point_of_sale_rounded, size: 14),
                                selected: draft.source == 'CASHIER_MANUAL',
                                onSelected: isSubmitting
                                    ? null
                                    : (selected) {
                                        if (selected) {
                                          setState(() {
                                            widget.controller.setOrderSource('CASHIER_MANUAL');
                                          });
                                        }
                                      },
                              ),
                              ChoiceChip(
                                label: const Text('WhatsApp'),
                                avatar: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                                selected: draft.source == 'WHATSAPP',
                                onSelected: isSubmitting
                                    ? null
                                    : (selected) {
                                        if (selected) {
                                          setState(() {
                                            widget.controller.setOrderSource('WHATSAPP');
                                          });
                                        }
                                      },
                              ),
                              ChoiceChip(
                                label: const Text('GoFood'),
                                avatar: const Icon(Icons.delivery_dining_rounded, size: 14),
                                selected: draft.source == 'GOFOOD',
                                onSelected: isSubmitting
                                    ? null
                                    : (selected) {
                                        if (selected) {
                                          setState(() {
                                            widget.controller.setOrderSource('GOFOOD');
                                          });
                                        }
                                      },
                              ),
                              ChoiceChip(
                                label: const Text('GrabFood'),
                                avatar: const Icon(Icons.delivery_dining_rounded, size: 14),
                                selected: draft.source == 'GRABFOOD',
                                onSelected: isSubmitting
                                    ? null
                                    : (selected) {
                                        if (selected) {
                                          setState(() {
                                            widget.controller.setOrderSource('GRABFOOD');
                                          });
                                        }
                                      },
                              ),
                              ChoiceChip(
                                label: const Text('ShopeeFood'),
                                avatar: const Icon(Icons.fastfood_rounded, size: 14),
                                selected: draft.source == 'SHOPEEFOOD',
                                onSelected: isSubmitting
                                    ? null
                                    : (selected) {
                                        if (selected) {
                                          setState(() {
                                            widget.controller.setOrderSource('SHOPEEFOOD');
                                          });
                                        }
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Divider(),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Jenis Layanan:',
                                style: AppTypography.labelSmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: draft.isTakeaway
                                        ? AppColors.warningBg
                                        : AppColors.surfaceVariant,
                                    borderRadius: AppSpacing.borderRadiusSm,
                                    border: Border.all(
                                      color: draft.isTakeaway
                                          ? AppColors.warning
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    draft.isTakeaway
                                        ? 'Bungkus / Takeaway'
                                        : 'Makan di Tempat (Dine-in)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: draft.isTakeaway
                                          ? AppColors.warning
                                          : AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (draft.isTakeaway &&
                              draft.takeawayNotes != null &&
                              draft.takeawayNotes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Catatan Kemasan: ${draft.takeawayNotes}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Items List Header
                    const Text(
                      'Rincian Pesanan:',
                      style: AppTypography.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // Items List
                    ...draft.items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item.quantity}x ${item.menuItem.name}',
                                      style: AppTypography.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (item.modifierSummary.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.modifierSummary,
                                        style: AppTypography.bodySmall,
                                      ),
                                    ],
                                    if (item.notes.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Catatan: ${item.notes}',
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.primary,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Rp ${item.lineTotal}',
                                style: AppTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: AppSpacing.md),

                    // 4. Payment Selection Card
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Status Pembayaran:',
                                style: AppTypography.labelSmall,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _payNow
                                      ? const Color(0xFFE8F5E9)
                                      : const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _payNow ? 'LUNAS' : 'BELUM BAYAR',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _payNow
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFFC62828),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => setState(() => _payNow = true),
                                  icon: Icon(
                                    _payNow
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 16,
                                    color: _payNow
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                  ),
                                  label: const Text('Bayar Langsung'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: _payNow
                                        ? const Color(0xFFFFF7ED)
                                        : Colors.white,
                                    side: BorderSide(
                                      color: _payNow
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => setState(() => _payNow = false),
                                  icon: Icon(
                                    !_payNow
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 16,
                                    color: !_payNow
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                  ),
                                  label: const Text('Bayar Nanti'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: !_payNow
                                        ? const Color(0xFFFFF7ED)
                                        : Colors.white,
                                    side: BorderSide(
                                      color: !_payNow
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_payNow) ...[
                            const SizedBox(height: AppSpacing.md),
                            const Divider(),
                            const SizedBox(height: AppSpacing.xs),
                            // Metode Pembayaran
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => setState(() => _paymentMethodIndex = 0),
                                    icon: Icon(
                                      Icons.payments_rounded,
                                      size: 16,
                                      color: _paymentMethodIndex == 0
                                          ? Colors.white
                                          : AppColors.primary,
                                    ),
                                    label: const Text(
                                      'Tunai (Cash)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: _paymentMethodIndex == 0
                                          ? AppColors.primary
                                          : Colors.white,
                                      foregroundColor: _paymentMethodIndex == 0
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      side: BorderSide(
                                        color: _paymentMethodIndex == 0
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => setState(() => _paymentMethodIndex = 1),
                                    icon: Icon(
                                      Icons.qr_code_scanner_rounded,
                                      size: 16,
                                      color: _paymentMethodIndex == 1
                                          ? Colors.white
                                          : AppColors.primary,
                                    ),
                                    label: const Text(
                                      'Non-Tunai (QRIS)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: _paymentMethodIndex == 1
                                          ? AppColors.primary
                                          : Colors.white,
                                      foregroundColor: _paymentMethodIndex == 1
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      side: BorderSide(
                                        color: _paymentMethodIndex == 1
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (isCash) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _buildPresetChip('Uang Pas', draft.totalAmount),
                                  _buildPresetChip('Rp 20.000', 20000),
                                  _buildPresetChip('Rp 50.000', 50000),
                                  _buildPresetChip('Rp 100.000', 100000),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(
                                controller: _cashInputController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Uang Tunai Diterima',
                                  prefixText: 'Rp ',
                                  prefixStyle:
                                      const TextStyle(fontWeight: FontWeight.bold),
                                  filled: true,
                                  fillColor: const Color(0xFFFAFAFA),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: AppColors.border,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                onChanged: _onCashInputChanged,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isCashValid
                                      ? const Color(0xFFE8F5E9)
                                      : const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isCashValid
                                          ? 'Uang Kembalian:'
                                          : 'Uang Kurang:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isCashValid
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFC62828),
                                      ),
                                    ),
                                    Text(
                                      _formatRupiah(
                                        change >= 0 ? change : -change,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: isCashValid
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFC62828),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 32,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'QRIS / Transfer Gerai',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'Nominal pas ${_formatRupiah(draft.totalAmount)}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // 3. Footer: Total Amount & Primary Submit Button
            // Criteria #4: Submit button is keyboard-safe and disabled during request
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Total Pembayaran',
                          style: AppTypography.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Rp ${draft.totalAmount}',
                        style: AppTypography.display.copyWith(
                          fontSize: 22,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: isSubmitting
                        ? 'Memproses Pesanan...'
                        : 'Kirim & Buat Pesanan',
                    icon: isSubmitting ? null : Icons.check_circle_rounded,
                    isFullWidth: true,
                    // Criteria #2 & #4: Double-tap locked and disabled during submission
                    onPressed: (isSubmitting ||
                            (_payNow && isCash && !isCashValid))
                        ? null
                        : () async {
                            widget.controller.setPaymentInfo(
                              paymentStatus: _payNow ? 'PAID' : 'UNPAID',
                              paymentMethod: _payNow
                                  ? (isCash ? 'CASH' : 'QRIS')
                                  : null,
                            );
                            final order = await widget.controller.submitOrder(
                              submitFn: widget.submitFn,
                            );
                            if (order != null && context.mounted) {
                              if (widget.onOrderCreated != null) {
                                widget.onOrderCreated!(order);
                              } else {
                                Navigator.of(context).pop(order);
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
