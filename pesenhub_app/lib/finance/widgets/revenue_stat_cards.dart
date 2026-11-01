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
        final isCompact = constraints.maxWidth < 640;

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
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildMetricTile(statItems[0])),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: _buildMetricTile(statItems[1])),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(child: _buildMetricTile(statItems[2])),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: _buildMetricTile(statItems[3])),
                    ],
                  ),
                ],
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
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative background accent
          Positioned(
            right: -10,
            top: -10,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.emerald.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.emeraldLight,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.emeraldLight.withValues(
                                  alpha: 0.8,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'TOTAL OMSET BERSIH',
                            maxLines: 1,
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
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.trending_up_rounded,
                          size: 13,
                          color: AppColors.emeraldLight,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Realisasi',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  summary.formattedNetRevenue,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1.0,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Omset riil yang telah diterima setelah potongan diskon',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.iconColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: AppColors.neutralTextMuted,
            ),
          ),
          const SizedBox(height: 3),
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
          const SizedBox(height: 1),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
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
