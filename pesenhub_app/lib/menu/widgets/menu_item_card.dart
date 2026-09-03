import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../models/menu_item.dart';

/// MenuItemCard renders a scannable menu item with price, description, and availability controls.
/// Fulfills Issue #27 Acceptance Criteria #1 and #2.
class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final ValueChanged<MenuItem>? onSelect;

  const MenuItemCard({super.key, required this.item, this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bool isAvailable = item.isAvailable;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: isAvailable && onSelect != null ? () => onSelect!(item) : null,
      borderSide: !isAvailable
          ? const BorderSide(color: AppColors.border, width: 1)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Header: Name & Status / Category Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isAvailable
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (!isAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.errorBg,
                        borderRadius: AppSpacing.borderRadiusSm,
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        'Habis',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                        ),
                      ),
                    )
                  else if (item.isDrink)
                    const Icon(
                      Icons.local_drink_rounded,
                      size: 16,
                      color: AppColors.info,
                    ),
                ],
              ),
              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
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
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // 2. Price & Action Button stacked for overflow resilience
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rp ${item.priceAmount}',
                style: AppTypography.bodyLarge.copyWith(
                  color: isAvailable ? AppColors.primary : AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              // Criteria #2: Item unavailable cannot be added (onPressed: null)
              AppButton(
                label: item.hasModifiers ? '+ Kustom' : '+ Tambah',
                icon: item.hasModifiers
                    ? Icons.tune_rounded
                    : Icons.add_rounded,
                height: 32,
                isFullWidth: true,
                onPressed: isAvailable && onSelect != null
                    ? () => onSelect!(item)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
