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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorderModern),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidianDark.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.coralBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.coralBorder),
                    ),
                    child: const Icon(
                      Icons.leaderboard_rounded,
                      size: 18,
                      color: AppColors.coral,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Paling Diminati',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: AppColors.obsidianDark,
                      ),
                    ),
                  ),
                ],
              ),
              // Segmented switch
              Container(
                decoration: BoxDecoration(
                  color: AppColors.slateBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorderModern),
                ),
                padding: const EdgeInsets.all(3),
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.neutralTextMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              alignment: Alignment.center,
              child: const Text(
                'Belum ada data penjualan pada periode ini.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.neutralTextMuted,
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.obsidianDark.withValues(alpha: 0.05),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? AppColors.indigo : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow({required int rank, required TopProduct item}) {
    final Color badgeColor;
    final Color badgeText;
    if (rank == 1) {
      badgeColor = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFD97706);
    } else if (rank == 2) {
      badgeColor = const Color(0xFFF1F5F9);
      badgeText = const Color(0xFF475569);
    } else if (rank == 3) {
      badgeColor = const Color(0xFFFFEDD5);
      badgeText = const Color(0xFFEA580C);
    } else {
      badgeColor = AppColors.slateBg;
      badgeText = AppColors.neutralTextMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.slateBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorderModern),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: badgeText,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
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
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidianDark,
                  ),
                ),
                Text(
                  '${item.quantity} porsi terjual',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.neutralTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.formattedRevenue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.obsidianDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
