import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../models/menu_item.dart';
import 'menu_image_view.dart';

/// MenuItemCard renders a scannable menu item with price, description, and availability controls.
/// Fulfills Issue #27 Acceptance Criteria #1 and #2.
class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final String? categoryName;
  final ValueChanged<MenuItem>? onSelect;
  final bool compact;

  const MenuItemCard({
    super.key,
    required this.item,
    this.categoryName,
    this.onSelect,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAvailable = item.isAvailable;

    if (compact) return _buildCompactCard(isAvailable);

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
              if (categoryName != null && categoryName!.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Text(
                    categoryName!,
                    style: const TextStyle(
                      color: Color(0xFFC2410C),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.imageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: MenuImageView(item: item, width: 56, height: 56),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
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
                    )
                  else if (item.hasSpiceLevel)
                    const Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: AppColors.error,
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
                CurrencyFormatter.formatRupiah(item.priceAmount),
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

  Widget _buildCompactCard(bool isAvailable) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isAvailable && onSelect != null ? () => onSelect!(item) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: MenuImageView(item: item, width: 72, height: 72),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (categoryName != null && categoryName!.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFFEDD5)),
                        ),
                        child: Text(
                          categoryName!,
                          style: const TextStyle(
                            color: Color(0xFFC2410C),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isAvailable
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                              fontSize: 13,
                              height: 1.18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!isAvailable)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.errorBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Habis',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (item.description case final description?) ...[
                      if (description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatRupiah(item.priceAmount),
                            style: TextStyle(
                              color: isAvailable
                                  ? const Color(0xFFE5573F)
                                  : AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 32,
                          child: ElevatedButton(
                            onPressed: isAvailable && onSelect != null
                                ? () => onSelect!(item)
                                : null,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              backgroundColor: const Color(0xFFE5573F),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              item.hasModifiers ? 'Pilih' : 'Tambah',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRupiah(int amount) => CurrencyFormatter.formatRupiah(amount);
}
