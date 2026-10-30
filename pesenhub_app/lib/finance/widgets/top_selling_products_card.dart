import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/top_products.dart';

class TopSellingProductsCard extends StatefulWidget {
  final TopProductsResponse topProducts;

  const TopSellingProductsCard({super.key, required this.topProducts});

  @override
  State<TopSellingProductsCard> createState() => _TopSellingProductsCardState();
}

class _TopSellingProductsCardState extends State<TopSellingProductsCard> {
  int _tabIndex = 0; // 0: Menu Terlaris, 1: Topping Terlaris

  @override
  Widget build(BuildContext context) {
    final items = _tabIndex == 0
        ? widget.topProducts.topProducts
        : widget.topProducts.topToppings;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.leaderboard_rounded,
                    size: 18,
                    color: AppColors.terracotta,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Paling Diminati',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              // Segmented switch
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceWarm,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabButton(
                      label: 'Menu',
                      index: 0,
                      keyName: 'top-menus-tab',
                    ),
                    _buildTabButton(
                      label: 'Topping',
                      index: 1,
                      keyName: 'top-toppings-tab',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '5 item dengan penjualan dan kontribusi omset tertinggi',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              alignment: Alignment.center,
              child: const Text(
                'Belum ada data penjualan pada periode ini.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            )
          else
            Column(
              children: items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _buildItemRow(rank: idx + 1, item: item),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required int index,
    required String keyName,
  }) {
    final isSelected = _tabIndex == index;
    return InkWell(
      key: Key(keyName),
      onTap: () => setState(() => _tabIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.terracotta : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow({required int rank, required TopProduct item}) {
    final Color badgeColor;
    final Color badgeText;
    if (rank == 1) {
      badgeColor = const Color(0xFFFFD700);
      badgeText = const Color(0xFF7A5900);
    } else if (rank == 2) {
      badgeColor = const Color(0xFFC0C0C0);
      badgeText = const Color(0xFF4A4A4A);
    } else if (rank == 3) {
      badgeColor = const Color(0xFFCD7F32);
      badgeText = Colors.white;
    } else {
      badgeColor = AppColors.surfaceWarm;
      badgeText = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: badgeText,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${item.quantity} porsi terjual',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.formattedRevenue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
