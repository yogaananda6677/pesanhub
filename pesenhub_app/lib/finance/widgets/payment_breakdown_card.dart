import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/financial_summary.dart';
import 'donut_pie_chart.dart';

class PaymentBreakdownCard extends StatelessWidget {
  final FinancialSummary summary;

  const PaymentBreakdownCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final cashRatio = summary.cashRatio;
    final digitalRatio = summary.digitalRatio;
    final cashPct = (cashRatio * 100).toStringAsFixed(1);
    final digitalPct = (digitalRatio * 100).toStringAsFixed(1);

    final segments = [
      PieChartSegment(
        value: summary.cashRevenue.toDouble(),
        color: AppColors.emerald,
        label: 'Tunai (Cash)',
        subtitle: 'Masuk kas laci kasir',
        icon: Icons.payments_outlined,
      ),
      PieChartSegment(
        value: summary.digitalRevenue.toDouble(),
        color: AppColors.indigo,
        label: 'Non-Tunai (QRIS)',
        subtitle: 'Masuk rekening settled',
        icon: Icons.qr_code_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        final tiles = [
          _buildBreakdownTile(
            title: 'Tunai (Cash)',
            nominal: summary.formattedCashRevenue,
            percentage: '$cashPct%',
            subtitle: 'Masuk kas laci kasir',
            color: AppColors.emerald,
            bgColor: AppColors.emeraldBg,
            borderColor: AppColors.emeraldBorder,
            icon: Icons.payments_outlined,
          ),
          _buildBreakdownTile(
            title: 'Non-Tunai (QRIS)',
            nominal: summary.formattedDigitalRevenue,
            percentage: '$digitalPct%',
            subtitle: 'Masuk rekening settled',
            color: AppColors.indigo,
            bgColor: AppColors.indigoBg,
            borderColor: AppColors.indigoBorder,
            icon: Icons.qr_code_rounded,
          ),
        ];

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorderModern),
            boxShadow: [
              BoxShadow(
                color: AppColors.obsidianDark.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.indigoBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.indigoBorder),
                    ),
                    child: const Icon(
                      Icons.pie_chart_rounded,
                      size: 18,
                      color: AppColors.indigo,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Breakdown Metode Pembayaran',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: AppColors.obsidianDark,
                          ),
                        ),
                        Text(
                          'Pemisahan pendapatan riil Tunai & Non-Tunai',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.neutralTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Visual Donut Chart Section
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                  horizontal: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.slateBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorderModern),
                ),
                child: isWide
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildDonutView(segments, cashPct, digitalPct),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              children: [
                                tiles[0],
                                const SizedBox(height: AppSpacing.sm),
                                tiles[1],
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Center(
                            child: _buildDonutView(
                              segments,
                              cashPct,
                              digitalPct,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          tiles[0],
                          const SizedBox(height: AppSpacing.sm),
                          tiles[1],
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Multi-color Mini Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      if (cashRatio > 0)
                        Flexible(
                          flex: (cashRatio * 1000).toInt().clamp(1, 1000),
                          child: Container(color: AppColors.emerald),
                        ),
                      if (digitalRatio > 0)
                        Flexible(
                          flex: (digitalRatio * 1000).toInt().clamp(1, 1000),
                          child: Container(color: AppColors.indigo),
                        ),
                      if (cashRatio == 0 && digitalRatio == 0)
                        Expanded(
                          child: Container(color: AppColors.outlineVariant),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDonutView(
    List<PieChartSegment> segments,
    String cashPct,
    String digitalPct,
  ) {
    final total = summary.cashRevenue + summary.digitalRevenue;

    return DonutPieChart(
      segments: segments,
      size: 150,
      strokeWidth: 20,
      centerWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            total > 0
                ? (summary.cashRevenue >= summary.digitalRevenue
                      ? Icons.payments_outlined
                      : Icons.qr_code_rounded)
                : Icons.donut_large_rounded,
            size: 18,
            color: total > 0
                ? AppColors.obsidianLight
                : AppColors.neutralTextMuted,
          ),
          const SizedBox(height: 2),
          Text(
            total > 0
                ? (summary.cashRevenue >= summary.digitalRevenue
                      ? '$cashPct% Tunai'
                      : '$digitalPct% QRIS')
                : 'Kosong',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidianDark,
            ),
          ),
          const Text(
            'Metode Utama',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.neutralTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownTile({
    required String title,
    required String nominal,
    required String percentage,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(icon, size: 14, color: color),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  percentage,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            nominal,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: AppColors.obsidianDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.neutralTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}
