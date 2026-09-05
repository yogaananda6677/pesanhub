import 'package:flutter/material.dart';
import '../../queue/models/queue_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_status_badge.dart';

/// KdsTicketCard renders a kitchen display production ticket.
/// Fulfills Issue #30 Criteria #1, #2, #3, and #4.
class KdsTicketCard extends StatelessWidget {
  final QueueOrder order;
  final DateTime now;
  final bool isProcessing;
  final VoidCallback? onQuickAction;

  const KdsTicketCard({
    super.key,
    required this.order,
    required this.now,
    this.isProcessing = false,
    this.onQuickAction,
  });

  String _formatElapsed(DateTime createdAt, DateTime current) {
    final diff = current.difference(createdAt);
    if (diff.inMinutes < 1) return '< 1m';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}j ${diff.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final bool isOverdue = order.isOverdueAt(now);
    final String elapsedText = _formatElapsed(order.createdAt, now);

    final drinks = order.items.where((i) => i.isDrink).toList();
    final foodItems = order.items.where((i) => !i.isDrink).toList();

    // Contextual 1-tap action
    final bool isAccepted = order.orderStatus == 'ACCEPTED';
    final String actionLabel = isAccepted ? 'Mulai Masak' : 'Tandai Siap';
    final IconData actionIcon = isAccepted
        ? Icons.outdoor_grill_rounded
        : Icons.done_all_rounded;

    return AppCard(
      borderSide: isOverdue
          ? const BorderSide(color: AppColors.error, width: 2)
          : BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Overdue Banner (Criteria #2)
          if (isOverdue) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'TERLAMBAT (> 15 mnt) • $elapsedText',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // 2. Ticket Header
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                order.orderNumber,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!isOverdue) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            elapsedText,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  AppStatusBadge.order(order.orderStatus),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Customer and Source Badges
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppStatusBadge.source(order.source),
              Text(
                '• ${order.customerName}',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Takeaway & Packaging Notes (Criteria #3)
          if (order.isTakeaway) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.takeout_dining_rounded,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      order.takeawayNotes != null &&
                              order.takeawayNotes!.isNotEmpty
                          ? 'Bungkus: ${order.takeawayNotes}'
                          : 'Bungkus / Takeaway',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),

          // 3. Food Items (Kitchen / Wok)
          ...foodItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                        child: Text(
                          '${item.quantity}x',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item.name,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(left: 30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                        child: Text(
                          item.notes!,
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: item.notes!.toLowerCase().contains('pedas')
                                ? AppColors.error
                                : AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 4. Barista Drinks Section (Criteria #3)
          if (drinks.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.infoBg.withValues(alpha: 0.3),
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_cafe_rounded,
                        size: 14,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Minuman Barista (${drinks.length})',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.info,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...drinks.map(
                    (drink) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${drink.quantity}x ${drink.name}${drink.notes != null && drink.notes!.isNotEmpty ? ' (${drink.notes})' : ''}',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // 5. 1-Tap Quick Action Button (Criteria #4)
          AppButton(
            label: isProcessing ? 'Memproses...' : actionLabel,
            icon: isProcessing ? null : actionIcon,
            isFullWidth: true,
            onPressed: isProcessing ? null : onQuickAction,
          ),
        ],
      ),
    );
  }
}
