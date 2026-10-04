import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_card.dart';
import '../models/cart_item.dart';

/// CartItemTile renders a scannable line item card in the cashier's active cart.
class CartItemTile extends StatelessWidget {
  final CartItem item;
  final ValueChanged<int> onUpdateQuantity;
  final VoidCallback onRemove;
  final VoidCallback? onEdit;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onUpdateQuantity,
    required this.onRemove,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header: Name, Drink icon, Edit & Remove buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.isDrink) ...[
                const Icon(
                  Icons.local_drink_rounded,
                  size: 16,
                  color: AppColors.info,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  item.menuItem.name,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onEdit != null) ...[
                IconButton(
                  key: Key('edit-cart-item-${item.id}'),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  color: AppColors.primary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Ubah Pilihan Menu',
                  onPressed: onEdit,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onRemove,
              ),
            ],
          ),

          // 2. Modifiers & Notes
          if (item.modifierSummary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.modifierSummary,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
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
          const SizedBox(height: AppSpacing.sm),

          // 3. Price & Quantity Stepper
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rp ${item.lineTotal}',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Rp ${item.unitPrice} / porsi',
                      style: AppTypography.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 22,
                    ),
                    color: AppColors.primary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => onUpdateQuantity(item.quantity - 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Text(
                      '${item.quantity}',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 22,
                    ),
                    color: AppColors.primary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => onUpdateQuantity(item.quantity + 1),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
