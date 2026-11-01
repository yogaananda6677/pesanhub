import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorderModern),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidianDark.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Full-width Title Row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.coralBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.coralBorder),
                ),
                child: const Icon(
                  Icons.leaderboard_rounded,
                  size: 20,
                  color: AppColors.coral,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Paling Diminati',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.obsidianDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sub-row: Subtitle & Segmented Tab Switch with Wrap for zero overflow
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                _tabIndex == 0
                    ? '5 item menu omset tertinggi'
                    : '5 item topping paling laris',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.slate,
                ),
              ),
              // Segmented Capsule Toggle matching mockup Screen 2 & 3
              LayoutBuilder(
                builder: (context, boxConstraints) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: boxConstraints.maxWidth,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F8),
                          borderRadius: BorderRadius.circular(20),
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
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Items List (matching Screen 3 "Today's records")
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              alignment: Alignment.center,
              child: const Text(
                'Belum ada data penjualan pada periode ini',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.neutralTextMuted,
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _buildProductTile(items[i], i + 1),
                ],
              ],
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
    return GestureDetector(
      key: Key(keyName),
      onTap: () => setState(() => _tabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.obsidianDark.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? AppColors.obsidianDark : AppColors.slate,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductTile(TopProduct product, int rank) {
    Color rankColor;
    Color rankBg;
    if (rank == 1) {
      rankColor = const Color(0xFFD97706);
      rankBg = const Color(0xFFFEF3C7);
    } else if (rank == 2) {
      rankColor = const Color(0xFF475569);
      rankBg = const Color(0xFFF1F5F9);
    } else if (rank == 3) {
      rankColor = const Color(0xFF9A3412);
      rankBg = const Color(0xFFFFEDD5);
    } else {
      rankColor = AppColors.slate;
      rankBg = const Color(0xFFF8FAFC);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderModern),
      ),
      child: Row(
        children: [
          // Circular Rank Badge matching Screen 3
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rankBg,
              shape: BoxShape.circle,
              border: Border.all(color: rankColor.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: AppColors.obsidianDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${product.quantitySold} porsi terjual',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.slate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              CurrencyFormatter.formatRupiah(product.totalSales),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: AppColors.obsidianDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
