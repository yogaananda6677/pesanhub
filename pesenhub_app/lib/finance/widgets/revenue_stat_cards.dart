import 'dart:math' as math;
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

        final netCard = _buildNetRevenueBanner(constraints.maxWidth);
        final statItems = [
          _StatData(
            title: 'Omset Kotor',
            value: summary.formattedGrossRevenue,
            subtitle: 'Sebelum diskon',
            icon: Icons.storefront_rounded,
            iconColor: AppColors.indigo,
            iconBg: AppColors.indigoBg,
            progress: 1.0,
          ),
          _StatData(
            title: 'Total Diskon',
            value: summary.formattedTotalDiscount,
            subtitle: 'Promo & potongan',
            icon: Icons.local_offer_rounded,
            iconColor: AppColors.amberModern,
            iconBg: AppColors.amberBgModern,
            progress: summary.grossRevenue > 0
                ? (summary.totalDiscount / summary.grossRevenue).clamp(
                    0.05,
                    1.0,
                  )
                : 0.1,
          ),
          _StatData(
            title: 'Pesanan Sukses',
            value: '${summary.totalOrders}',
            subtitle: 'Lunas / selesai',
            icon: Icons.receipt_long_rounded,
            iconColor: AppColors.emerald,
            iconBg: AppColors.emeraldBg,
            progress: summary.totalOrders > 0 ? 0.85 : 0.05,
          ),
          _StatData(
            title: 'Rata-rata Order',
            value: summary.formattedAverageOrderValue,
            subtitle: 'Nilai per pesanan',
            icon: Icons.analytics_rounded,
            iconColor: AppColors.sky,
            iconBg: AppColors.skyBg,
            progress: summary.averageOrderValue > 0 ? 0.70 : 0.05,
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

  Widget _buildNetRevenueBanner(double maxWidth) {
    // Only show circular gauge if there's enough horizontal width
    final showGauge = maxWidth >= 480;
    final ratio = summary.grossRevenue > 0
        ? (summary.netRevenue / summary.grossRevenue).clamp(0.0, 1.0)
        : 1.0;
    final pctText = '${(ratio * 100).toInt()}%';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
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
          // Subtle glow
          Positioned(
            right: -10,
            top: -10,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.emerald.withValues(alpha: 0.1),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        summary.formattedNetRevenue,
                        style: const TextStyle(
                          fontSize: 32,
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
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Container(
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
                              'Realisasi Transaksi',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showGauge) ...[
                const SizedBox(width: AppSpacing.md),
                // Mini Circular Radial Gauge matching mockup Screen 1
                SizedBox(
                  width: 76,
                  height: 76,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(76, 76),
                        painter: _RadialGaugePainter(
                          progress: ratio,
                          trackColor: const Color(0xFF334155),
                          progressColor: AppColors.emeraldLight,
                          strokeWidth: 8,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                pctText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const Text(
                                'Realisasi',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorderModern),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidianDark.withValues(alpha: 0.025),
            blurRadius: 12,
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
              Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: AppColors.slateLight.withValues(alpha: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 8),
          // Mini progress track matching Screen 2 "Monthly Progress Summary"
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 4,
              color: item.iconBg,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: item.progress.clamp(0.05, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: item.iconColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
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
  final double progress;

  const _StatData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.progress,
  });
}

class _RadialGaugePainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  const _RadialGaugePainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = (progress * 2 * math.pi).clamp(0.01, 2 * math.pi);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadialGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
