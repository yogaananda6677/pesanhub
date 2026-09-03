import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_card.dart';

/// OrderStatusTimeline visualizes the order lifecycle progress.
/// Fulfills Issue #29 Criteria #3 (Order lifecycle strictly separated from payment status).
class OrderStatusTimeline extends StatelessWidget {
  final String orderStatus;

  const OrderStatusTimeline({super.key, required this.orderStatus});

  static const _stages = [
    _TimelineStage(
      statusKey: 'ACCEPTED',
      label: 'Diterima',
      icon: Icons.receipt_rounded,
    ),
    _TimelineStage(
      statusKey: 'PREPARING',
      label: 'Memasak',
      icon: Icons.soup_kitchen_rounded,
    ),
    _TimelineStage(
      statusKey: 'READY_FOR_PICKUP',
      label: 'Siap Diambil',
      icon: Icons.check_circle_rounded,
    ),
    _TimelineStage(
      statusKey: 'COMPLETED',
      label: 'Selesai',
      icon: Icons.task_alt_rounded,
    ),
  ];

  int _currentStageIndex() {
    switch (orderStatus) {
      case 'PENDING':
        return 0;
      case 'ACCEPTED':
        return 0;
      case 'PREPARING':
        return 1;
      case 'READY_FOR_PICKUP':
        return 2;
      case 'COMPLETED':
        return 3;
      default:
        return -1; // REJECTED or CANCELLED
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentStageIndex();
    final isTerminated =
        orderStatus == 'REJECTED' || orderStatus == 'CANCELLED';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Siklus Tahapan Pesanan',
                  style: AppTypography.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isTerminated
                      ? AppColors.errorBg
                      : AppColors.primaryContainer,
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Text(
                  orderStatus,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isTerminated ? AppColors.error : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          if (isTerminated) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel_rounded, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      orderStatus == 'REJECTED'
                          ? 'Pesanan ini telah ditolak oleh staf outlet.'
                          : 'Pesanan ini telah dibatalkan.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: List.generate(_stages.length * 2 - 1, (index) {
                if (index.isOdd) {
                  // Connecting line
                  final stageBefore = index ~/ 2;
                  final isPassed = stageBefore < currentIndex;
                  return Expanded(
                    child: Container(
                      height: 3,
                      color: isPassed ? AppColors.primary : AppColors.border,
                    ),
                  );
                }

                // Stage node
                final stageIndex = index ~/ 2;
                final stage = _stages[stageIndex];
                final isCompleted = stageIndex < currentIndex;
                final isCurrent = stageIndex == currentIndex;

                Color nodeBg = AppColors.surfaceVariant;
                Color iconColor = AppColors.textSecondary;
                Color borderColor = AppColors.border;

                if (isCompleted) {
                  nodeBg = AppColors.primary;
                  iconColor = Colors.white;
                  borderColor = AppColors.primary;
                } else if (isCurrent) {
                  nodeBg = AppColors.primaryContainer;
                  iconColor = AppColors.primary;
                  borderColor = AppColors.primary;
                }

                return SizedBox(
                  width: 48,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: nodeBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: borderColor, width: 2),
                        ),
                        child: Icon(stage.icon, size: 16, color: iconColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stage.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: isCurrent
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineStage {
  final String statusKey;
  final String label;
  final IconData icon;

  const _TimelineStage({
    required this.statusKey,
    required this.label,
    required this.icon,
  });
}
