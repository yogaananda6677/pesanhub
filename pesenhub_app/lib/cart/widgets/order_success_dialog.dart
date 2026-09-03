import 'package:flutter/material.dart';
import '../../queue/models/queue_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_status_badge.dart';

/// OrderSuccessDialog displays confirmation after an order is submitted.
/// Fulfills Issue #28 Criteria #5 (success state).
class OrderSuccessDialog extends StatelessWidget {
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
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
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
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    AppStatusBadge.source(order.source),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pelanggan:', style: AppTypography.labelSmall),
                    Text(
                      order.customerName,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Layanan:', style: AppTypography.labelSmall),
                    Text(
                      order.isTakeaway
                          ? 'Bungkus / Takeaway'
                          : 'Makan di Tempat',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: order.isTakeaway
                            ? AppColors.warning
                            : AppColors.textPrimary,
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
                    Text(
                      'Rp ${order.totalAmount}',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 4. Action Buttons
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Pesanan Baru',
                  variant: AppButtonVariant.secondary,
                  onPressed: onNewOrder ?? () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Lihat di Antrean',
                  icon: Icons.list_alt_rounded,
                  onPressed: onViewQueue ?? () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
