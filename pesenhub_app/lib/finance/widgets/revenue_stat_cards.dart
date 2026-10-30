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
            iconColor: AppColors.accentBlue,
            iconBg: AppColors.accentBlueBg,
          ),
          _StatData(
            title: 'Total Diskon',
            value: summary.formattedTotalDiscount,
            subtitle: 'Promo & potongan',
            icon: Icons.local_offer_outlined,
            iconColor: AppColors.accentAmber,
            iconBg: AppColors.accentAmberBg,
          ),
          _StatData(
            title: 'Pesanan Sukses',
            value: '${summary.totalOrders}',
            subtitle: 'Lunas / selesai',
            icon: Icons.receipt_long_outlined,
            iconColor: AppColors.accentGreen,
            iconBg: AppColors.accentGreenBg,
          ),
          _StatData(
            title: 'Rata-rata Order',
            value: summary.formattedAverageOrderValue,
            subtitle: 'Nilai per pesanan',
            icon: Icons.analytics_outlined,
            iconColor: AppColors.terracotta,
            iconBg: AppColors.terracottaSoft,
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
          colors: [AppColors.terracotta, Color(0xFF6E2415)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.terracotta.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'TOTAL OMSET BERSIH',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white70,
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
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Omset riil yang telah diterima setelah potongan diskon',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(_StatData item) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.iconBg,
              borderRadius: BorderRadius.circular(10),
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
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
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
