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

/// OrderReviewDialog provides an explicit pre-submission review of the cashier's order.
/// Fulfills Issue #28 Criteria #1, #2, #3, and #4.
class OrderReviewDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final draft = controller.currentDraft;
        final bool isSubmitting = controller.isSubmitting;
        final String? errorMsg = controller.errorMessage;
        final String? discrepancyMsg = controller.discrepancyMessage;

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
                              Text(
                                draft.customerName,
                                style: AppTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.w700,
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
                                Text(
                                  draft.customerPhone!,
                                  style: AppTypography.bodyMedium,
                                ),
                              ],
                            ),
                          ],
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
                              Container(
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
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final order = await controller.submitOrder(
                              submitFn: submitFn,
                            );
                            if (order != null && context.mounted) {
                              if (onOrderCreated != null) {
                                onOrderCreated!(order);
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
