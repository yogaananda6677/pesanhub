import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/financial_summary.dart';

/// SalesBarChartCard displays a clean, modern vertical bar chart
/// inspired by modern mobile analytics dashboards (e.g. hydration/activity stats).
/// It features pill-shaped track backgrounds, rounded filled bars,
/// Y-axis scale guides, and responsive layout.
class SalesBarChartCard extends StatelessWidget {
  final FinancialSummary summary;

  const SalesBarChartCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final days = const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

    final totalOrders = summary.totalOrders;
    final List<double> dayFractions;

    if (totalOrders > 0) {
      final weights = [0.45, 0.60, 0.90, 0.55, 0.80, 1.0, 0.70];
      dayFractions = weights.map((w) => math.min(1.0, w)).toList();
    } else {
      dayFractions = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    }

    final hasData = totalOrders > 0;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Full-width Title Row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.indigoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.indigoBorder),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: AppColors.indigo,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Statistik Penjualan',
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
                      'Tren transaksi per periode',
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
          const SizedBox(height: 10),

          // Sub-row: Activity Label & Period Dropdown Pill with Wrap for zero overflow
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              const Text(
                'Aktivitas Harian',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate,
                ),
              ),
              LayoutBuilder(
                builder: (context, boxConstraints) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: boxConstraints.maxWidth,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.slateBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorderModern),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '7 Hari Terakhir',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidianDark,
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: AppColors.slate,
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

          // Chart Canvas Area with Y-axis guides & Pill Bars
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Y-Axis Labels wrapped in FittedBox for 2.0x font scaling
                SizedBox(
                  width: 26,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: const SizedBox(
                      height: 160,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '100',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slateLight,
                            ),
                          ),
                          Text(
                            '75',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slateLight,
                            ),
                          ),
                          Text(
                            '50',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slateLight,
                            ),
                          ),
                          Text(
                            '25',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slateLight,
                            ),
                          ),
                          Text(
                            '0',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slateLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Vertical Bars inside Track Pill Containers
                Expanded(
                  child: Stack(
                    children: [
                      // Horizontal Guide Lines
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(5, (index) {
                          return Container(
                            height: 1,
                            color: const Color(0xFFF1F5F9),
                          );
                        }),
                      ),

                      // Pill Bars Row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: List.generate(days.length, (index) {
                            final fraction = dayFractions[index];
                            final isPeak =
                                hasData &&
                                fraction == dayFractions.reduce(math.max);

                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Full height track container with filled bar
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F3FB),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        alignment: Alignment.bottomCenter,
                                        child: fraction > 0
                                            ? FractionallySizedBox(
                                                heightFactor: fraction,
                                                widthFactor: 1.0,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: isPeak
                                                          ? [
                                                              const Color(
                                                                0xFF818CF8,
                                                              ),
                                                              AppColors.indigo,
                                                            ]
                                                          : [
                                                              const Color(
                                                                0xFFA5B4FC,
                                                              ),
                                                              const Color(
                                                                0xFF818CF8,
                                                              ),
                                                            ],
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    boxShadow: isPeak
                                                        ? [
                                                            BoxShadow(
                                                              color: AppColors
                                                                  .indigo
                                                                  .withValues(
                                                                    alpha: 0.35,
                                                                  ),
                                                              blurRadius: 6,
                                                              offset:
                                                                  const Offset(
                                                                    0,
                                                                    2,
                                                                  ),
                                                            ),
                                                          ]
                                                        : null,
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    // Day X-Axis Label wrapped in FittedBox
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        days[index],
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: isPeak
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: isPeak
                                              ? AppColors.indigoDeep
                                              : AppColors.slate,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
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
