import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/financial_summary.dart';

class PaymentBreakdownCard extends StatelessWidget {
  final FinancialSummary summary;

  const PaymentBreakdownCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final cashRatio = summary.cashRatio;
    final digitalRatio = summary.digitalRatio;
    final cashPct = (cashRatio * 100).toStringAsFixed(1);
    final digitalPct = (digitalRatio * 100).toStringAsFixed(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final tiles = [
          _buildBreakdownTile(
            title: 'Tunai (Cash)',
            nominal: summary.formattedCashRevenue,
            percentage: '$cashPct%',
            subtitle: 'Masuk kas laci kasir',
            color: AppColors.accentGreen,
            icon: Icons.payments_outlined,
          ),
          _buildBreakdownTile(
            title: 'Non-Tunai (QRIS)',
            nominal: summary.formattedDigitalRevenue,
            percentage: '$digitalPct%',
            subtitle: 'Masuk rekening settled',
            color: AppColors.accentBlue,
            icon: Icons.qr_code_rounded,
          ),
        ];

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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlueBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.pie_chart_outline_rounded,
                      size: 18,
                      color: AppColors.accentBlue,
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
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Pemisahan pendapatan riil Tunai & Non-Tunai',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Multi-color Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      if (cashRatio > 0)
                        Flexible(
                          flex: (cashRatio * 1000).toInt().clamp(1, 1000),
                          child: Container(color: AppColors.accentGreen),
                        ),
                      if (digitalRatio > 0)
                        Flexible(
                          flex: (digitalRatio * 1000).toInt().clamp(1, 1000),
                          child: Container(color: AppColors.accentBlue),
                        ),
                      if (cashRatio == 0 && digitalRatio == 0)
                        Expanded(
                          child: Container(color: AppColors.outlineVariant),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Detail Tiles
              if (isCompact)
                Column(
                  children: [
                    tiles[0],
                    const SizedBox(height: AppSpacing.sm),
                    tiles[1],
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: tiles[0]),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: tiles[1]),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreakdownTile({
    required String title,
    required String nominal,
    required String percentage,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  percentage,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
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
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
