import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_card.dart';
import '../models/menu_item.dart';

/// MenuAvailabilityCard displays a menu item with scannable availability status,
/// version chip, and interactive toggle switch protected by role permissions.
/// Fulfills Issue #31 Acceptance Criteria #1, #2, #3, and #5.
class MenuAvailabilityCard extends StatelessWidget {
  final MenuItem item;
  final String categoryName;
  final bool isStaff;
  final bool isUpdating;
  final ValueChanged<bool>? onToggle;

  const MenuAvailabilityCard({
    super.key,
    required this.item,
    required this.categoryName,
    this.isStaff = true,
    this.isUpdating = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAvailable = item.isAvailable;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderSide: !isAvailable
          ? BorderSide(
              color: AppColors.error.withValues(alpha: 0.6),
              width: 1.5,
            )
          : const BorderSide(color: AppColors.border, width: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header: Name, SKU, Category Badge & Version Chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isAvailable
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          categoryName,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Text(
                          '•',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            item.sku,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Version Chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppSpacing.borderRadiusSm,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'v${item.version}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.description!,
              style: AppTypography.bodySmall.copyWith(
                color: isAvailable
                    ? AppColors.textSecondary
                    : AppColors.textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.sm),

          // 2. Price and Availability Toggle Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Price
              Expanded(
                child: Text(
                  'Rp ${item.priceAmount}',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isAvailable
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),

              // Status Badge & Interactive Toggle Switch
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isAvailable
                          ? AppColors.successBg
                          : AppColors.errorBg,
                      borderRadius: AppSpacing.borderRadiusSm,
                      border: Border.all(
                        color: isAvailable
                            ? AppColors.success.withValues(alpha: 0.3)
                            : AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAvailable
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 14,
                          color: isAvailable
                              ? AppColors.success
                              : AppColors.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isAvailable ? 'Tersedia' : 'Habis',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isAvailable
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),

                  // In-flight spinner or Toggle Switch
                  if (isUpdating)
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    )
                  else
                    Semantics(
                      label:
                          'Ubah ketersediaan ${item.name}. Status saat ini ${isAvailable ? "Tersedia" : "Habis"}',
                      toggled: isAvailable,
                      child: SizedBox(
                        height: 48,
                        child: Switch(
                          value: isAvailable,
                          activeThumbColor: AppColors.success,
                          activeTrackColor: AppColors.successBg,
                          inactiveThumbColor: AppColors.error,
                          inactiveTrackColor: AppColors.errorBg,
                          // Criteria #3: Disabled if not staff
                          onChanged: isStaff && onToggle != null
                              ? (val) => onToggle!(val)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Role guard hint if not staff
          if (!isStaff) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 12,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Hanya staf kasir yang dapat mengubah ketersediaan',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
