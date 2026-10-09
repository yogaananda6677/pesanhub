import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_card.dart';
import '../models/menu_item.dart';
import 'menu_image_view.dart';

/// MenuAvailabilityCard displays a menu item with scannable availability status,
/// version chip, and interactive toggle switch protected by role permissions.
/// Fulfills Issue #31 Acceptance Criteria #1, #2, #3, and #5.
class MenuAvailabilityCard extends StatelessWidget {
  final MenuItem item;
  final String categoryName;
  final bool isStaff;
  final bool isMutationEnabled;
  final bool isUpdating;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onEditPrice;

  const MenuAvailabilityCard({
    super.key,
    required this.item,
    required this.categoryName,
    this.isStaff = true,
    this.isMutationEnabled = true,
    this.isUpdating = false,
    this.onToggle,
    this.onEdit,
    this.onEditPrice,
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
          // 1. Header: Category badge, SKU, Name & Version Chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            categoryName,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            item.productType == 'TERANG_BULAN'
                                ? 'Terang Bulan'
                                : 'Martabak Telur',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.name,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: isAvailable
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Version Chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
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

          if (item.imageUrl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: MenuImageView(
                item: item,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                allowNetworkFallback: true,
              ),
            ),
          ],

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

          if (isStaff && (onEdit != null || onEditPrice != null)) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('edit-menu-${item.id}'),
                    onPressed: isMutationEnabled ? onEdit : null,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'Edit Menu',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('edit-price-${item.id}'),
                    onPressed: isMutationEnabled ? onEditPrice : null,
                    icon: const Icon(Icons.sell_outlined, size: 16),
                    label: const Text(
                      'Edit Harga',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

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
                  CurrencyFormatter.formatRupiah(item.priceAmount),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: isAvailable
                        ? AppColors.primary
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
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isAvailable
                          ? const Color(0xFFEBF7EE)
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isAvailable
                            ? const Color(0xFFBCE3C5)
                            : const Color(0xFFFECACA),
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
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFD32F2F),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isAvailable ? 'Stok tersedia' : 'Stok habis',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isAvailable
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFD32F2F),
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
                          onChanged:
                              isStaff && isMutationEnabled && onToggle != null
                              ? (val) => onToggle!(val)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          if (isStaff &&
              (item.hppAmount != null || item.channelPrices.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (item.hppAmount case final hpp?)
                  _PriceChip(label: 'HPP', amount: hpp),
                for (final channel in const [
                  'OFFLINE',
                  'GOFOOD',
                  'GRABFOOD',
                  'SHOPEEFOOD',
                ])
                  if (item.channelPrices[channel] case final amount?)
                    _PriceChip(label: channel, amount: amount),
              ],
            ),
          ],

          // Role guard hint if not staff
          if (!isStaff || !isMutationEnabled) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 12,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isStaff
                        ? 'Hubungkan backend untuk mengubah ketersediaan'
                        : 'Hanya staf kasir yang dapat mengubah ketersediaan',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
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

class _PriceChip extends StatelessWidget {
  final String label;
  final int amount;

  const _PriceChip({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        '$label · ${CurrencyFormatter.formatRupiah(amount)}',
        style: AppTypography.bodySmall,
      ),
    );
  }
}
