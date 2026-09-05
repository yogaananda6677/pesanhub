import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_status_badge.dart';
import '../models/queue_order.dart';

/// OrderQueueCard renders a scannable order in the unified queue.
/// Fulfills Issue #26 Acceptance Criteria #1, #3, and #5.
class OrderQueueCard extends StatelessWidget {
  final QueueOrder order;
  final DateTime? now;
  final void Function(QueueOrder order, String newStatus)? onStatusChanged;
  final VoidCallback? onTap;

  const OrderQueueCard({
    super.key,
    required this.order,
    this.now,
    this.onStatusChanged,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOverdue = now != null
        ? order.isOverdueAt(now!)
        : order.isOverdue;

    return AppCard(
      onTap: onTap,
      borderSide: isOverdue
          ? const BorderSide(color: AppColors.error, width: 2)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Overdue banner if applicable (Criteria #3)
          if (isOverdue) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.timer_off_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'TERLAMBAT (> 15 MENIT BELUM SELESAI)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // 2. Card Header: Order Number, Time, and Badges (Criteria #1)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.start,
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNumber,
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(order.formattedTime, style: AppTypography.bodySmall),
                    ],
                  ),
                ],
              ),
              // Source badge: CASHIER_MANUAL, CUSTOMER_WEB, WHATSAPP (Criteria #1)
              AppStatusBadge.source(order.source),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // 3. Customer Info & Badges
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                '${order.customerName} (${order.customerPhone})',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppStatusBadge.order(order.orderStatus),
                  AppStatusBadge.payment(order.paymentStatus),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),

          // 4. Takeaway / Packing Section (Criteria #3)
          if (order.isTakeaway) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pesanan Dibungkus (Takeaway)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (order.takeawayNotes != null &&
                            order.takeawayNotes!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Catatan Bungkus: ${order.takeawayNotes}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // 5. Drinks Highlight Section (Criteria #3)
          if (order.drinkItems.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.local_drink_rounded,
                        size: 16,
                        color: AppColors.info,
                      ),
                      SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Minuman / Barista',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ...order.drinkItems.map((drink) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${drink.quantity}x ${drink.name}${drink.notes != null ? ' (${drink.notes})' : ''}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            'Rp ${drink.subtotal}',
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // 6. Food Items List (Criteria #3)
          if (order.foodItems.isNotEmpty) ...[
            const Text('Makanan / Dapur:', style: AppTypography.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            ...order.foodItems.map((food) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${food.quantity}x ${food.name}',
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          'Rp ${food.subtotal}',
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    ),
                    if (food.notes != null && food.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppSpacing.md,
                          top: 2,
                        ),
                        child: Text(
                          'Catatan: ${food.notes}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppSpacing.sm),
          ],

          // 7. Total Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Total Pembayaran',
                  style: AppTypography.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Rp ${order.totalAmount}',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // 8. Contextual Action Buttons
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    switch (order.orderStatus) {
      case 'PENDING':
        return Row(
          children: [
            Expanded(
              child: AppButton.danger(
                label: 'Tolak',
                icon: Icons.cancel_outlined,
                onPressed: onStatusChanged != null
                    ? () => onStatusChanged!(order, 'REJECTED')
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: AppButton(
                label: 'Terima Pesanan',
                icon: Icons.check_circle_outline_rounded,
                onPressed: onStatusChanged != null
                    ? () => onStatusChanged!(order, 'ACCEPTED')
                    : null,
              ),
            ),
          ],
        );

      case 'ACCEPTED':
        return AppButton(
          label: 'Mulai Masak di Dapur',
          icon: Icons.outdoor_grill_rounded,
          isFullWidth: true,
          onPressed: onStatusChanged != null
              ? () => onStatusChanged!(order, 'PREPARING')
              : null,
        );

      case 'PREPARING':
        return AppButton(
          label: 'Tandai Siap Diambil',
          icon: Icons.shopping_bag_outlined,
          isFullWidth: true,
          onPressed: onStatusChanged != null
              ? () => onStatusChanged!(order, 'READY_FOR_PICKUP')
              : null,
        );

      case 'READY_FOR_PICKUP':
        return AppButton(
          label: 'Serahkan ke Pelanggan',
          icon: Icons.task_alt_rounded,
          isFullWidth: true,
          onPressed: onStatusChanged != null
              ? () => onStatusChanged!(order, 'COMPLETED')
              : null,
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
