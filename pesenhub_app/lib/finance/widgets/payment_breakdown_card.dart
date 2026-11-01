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
          _buildRecordTile(
            title: 'Tunai (Cash)',
            nominal: summary.formattedCashRevenue,
            percentage: '$cashPct%',
            subtitle: 'Masuk kas laci kasir',
            color: AppColors.emerald,
            bgColor: AppColors.emeraldBg,
            icon: Icons.payments_rounded,
          ),
          _buildRecordTile(
            title: 'Non-Tunai (QRIS)',
            nominal: summary.formattedDigitalRevenue,
            percentage: '$digitalPct%',
            subtitle: 'Masuk rekening settled',
            color: AppColors.indigo,
            bgColor: AppColors.indigoBg,
            icon: Icons.qr_code_2_rounded,
          ),
        ];

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
              // Card Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.indigoBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.indigoBorder),
                          ),
                          child: const Icon(
                            Icons.pie_chart_rounded,
                            size: 20,
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: AppColors.obsidianDark,
                                ),
                              ),
                              Text(
                                'Pemisahan pendapatan riil Tunai & Non-Tunai',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.slate,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: AppColors.slateLight.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Visual Circular Gauge / Donut Meter Section (matching Screen 3 mockup)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(20),
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

              // Multi-color Segmented Proportion Bar
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
      size: 156,
      strokeWidth: 20,
      centerWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: total > 0
                  ? (summary.cashRevenue >= summary.digitalRevenue
                        ? AppColors.emeraldBg
                        : AppColors.indigoBg)
                  : AppColors.slateBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              total > 0
                  ? (summary.cashRevenue >= summary.digitalRevenue
                        ? Icons.payments_rounded
                        : Icons.qr_code_2_rounded)
                  : Icons.donut_large_rounded,
              size: 20,
              color: total > 0
                  ? (summary.cashRevenue >= summary.digitalRevenue
                        ? AppColors.emerald
                        : AppColors.indigo)
                  : AppColors.neutralTextMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            total > 0
                ? (summary.cashRevenue >= summary.digitalRevenue
                      ? '$cashPct% Tunai'
                      : '$digitalPct% QRIS')
                : 'Kosong',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.obsidianDark,
              letterSpacing: -0.2,
            ),
          ),
          const Text(
            'Metode Utama',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile({
    required String title,
    required String nominal,
    required String percentage,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderModern),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidianDark.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Icon Avatar matching Screen 3 "Today's records"
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Title & Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: AppColors.obsidianDark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.slate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Nominal & Percentage Pill
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  nominal,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: AppColors.obsidianDark,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  percentage,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
