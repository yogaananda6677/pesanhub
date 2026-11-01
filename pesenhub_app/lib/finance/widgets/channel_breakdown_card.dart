import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/financial_summary.dart';
import 'donut_pie_chart.dart';

class ChannelBreakdownCard extends StatelessWidget {
  final FinancialSummary summary;

  const ChannelBreakdownCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final channels = [
      _ChannelData(
        key: 'CASHIER_MANUAL',
        name: 'Kasir POS Manual',
        subtitle: 'Pesanan langsung di kasir toko',
        icon: Icons.point_of_sale_rounded,
        color: AppColors.indigo,
      ),
      _ChannelData(
        key: 'WHATSAPP',
        name: 'WhatsApp Hermes',
        subtitle: 'Asisten AI WhatsApp Jenggirat',
        icon: Icons.chat_rounded,
        color: const Color(0xFF10B981),
      ),
      _ChannelData(
        key: 'CUSTOMER_WEB',
        name: 'Web Customer',
        subtitle: 'Pemesanan mandiri via browser',
        icon: Icons.language_rounded,
        color: AppColors.sky,
      ),
    ];

    final totalRev = summary.netRevenue > 0 ? summary.netRevenue : 1;
    final channelSegments = channels.map((ch) {
      final rev = summary.revenueByChannel[ch.key] ?? 0;
      return PieChartSegment(
        value: rev.toDouble(),
        color: ch.color,
        label: ch.name,
        icon: ch.icon,
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

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
                      color: AppColors.amberBgModern,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.amberBorderModern),
                    ),
                    child: const Icon(
                      Icons.hub_outlined,
                      size: 18,
                      color: AppColors.amberModern,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Distribusi Kanal Penjualan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: AppColors.obsidianDark,
                          ),
                        ),
                        Text(
                          'Porsi pendapatan kasir fisik vs online bot & web',
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

              // Visual Graphic representation
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.slateBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorderModern),
                ),
                child: isWide
                    ? Row(
                        children: [
                          DonutPieChart(
                            segments: channelSegments,
                            size: 130,
                            strokeWidth: 16,
                            centerWidget: const Icon(
                              Icons.storefront_rounded,
                              size: 22,
                              color: AppColors.obsidianLight,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              children: channels
                                  .map((ch) => _buildChannelItem(ch, totalRev))
                                  .toList(),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Center(
                            child: DonutPieChart(
                              segments: channelSegments,
                              size: 120,
                              strokeWidth: 16,
                              centerWidget: const Icon(
                                Icons.storefront_rounded,
                                size: 20,
                                color: AppColors.obsidianLight,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Column(
                            children: channels
                                .map((ch) => _buildChannelItem(ch, totalRev))
                                .toList(),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelItem(_ChannelData ch, int totalRev) {
    final rev = summary.revenueByChannel[ch.key] ?? 0;
    final orders = summary.ordersByChannel[ch.key] ?? 0;
    final ratio = (rev / totalRev).clamp(0.0, 1.0);
    final pct = (ratio * 100).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorderModern),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: ch.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(ch.icon, size: 14, color: ch.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidianDark,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: ch.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: ch.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  '$orders order ($pct%)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.neutralTextMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  CurrencyFormatter.formatRupiah(rev),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidianDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                backgroundColor: AppColors.slateBg,
                valueColor: AlwaysStoppedAnimation<Color>(ch.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelData {
  final String key;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;

  _ChannelData({
    required this.key,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
