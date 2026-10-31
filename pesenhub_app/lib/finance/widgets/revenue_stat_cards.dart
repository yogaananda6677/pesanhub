import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/financial_summary.dart';

class RevenueStatCards extends StatelessWidget {
  final FinancialSummary summary;

  const RevenueStatCards({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;

        final netCard = _buildNetRevenueBanner();
        final statItems = [
          _StatData(
            title: 'Omset Kotor',
            value: summary.formattedGrossRevenue,
            subtitle: 'Sebelum diskon',
            icon: Icons.storefront_outlined,
            iconColor: AppColors.indigo,
            iconBg: AppColors.indigoBg,
          ),
          _StatData(
            title: 'Total Diskon',
            value: summary.formattedTotalDiscount,
            subtitle: 'Promo & potongan',
            icon: Icons.local_offer_outlined,
            iconColor: AppColors.amberModern,
            iconBg: AppColors.amberBgModern,
          ),
          _StatData(
            title: 'Pesanan Sukses',
            value: '${summary.totalOrders}',
            subtitle: 'Lunas / selesai',
            icon: Icons.receipt_long_outlined,
            iconColor: AppColors.emerald,
            iconBg: AppColors.emeraldBg,
          ),
          _StatData(
            title: 'Rata-rata Order',
            value: summary.formattedAverageOrderValue,
            subtitle: 'Nilai per pesanan',
            icon: Icons.analytics_outlined,
            iconColor: AppColors.sky,
            iconBg: AppColors.skyBg,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            netCard,
            const SizedBox(height: AppSpacing.sm),
            if (isCompact)
              Column(
                children: statItems
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _buildMetricTile(item),
                      ),
                    )
                    .toList(),
              )
            else
              Row(
                children: [
                  for (int i = 0; i < statItems.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _buildMetricTile(statItems[i])),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildNetRevenueBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.obsidianDark, Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.obsidianLight.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidianDark.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.emeraldLight,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.emeraldLight.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'TOTAL OMSET BERSIH',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.emeraldLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              summary.formattedNetRevenue,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Omset riil yang telah diterima setelah potongan diskon',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(_StatData item) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderModern),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidianDark.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.iconColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    color: AppColors.neutralTextMuted,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: AppColors.obsidianDark,
                    ),
                  ),
                ),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  _StatData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
}
