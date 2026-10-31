import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/financial_summary.dart';

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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          Column(
            children: channels.map((ch) {
              final rev = summary.revenueByChannel[ch.key] ?? 0;
              final orders = summary.ordersByChannel[ch.key] ?? 0;
              final ratio = (rev / totalRev).clamp(0.0, 1.0);
              final pct = (ratio * 100).toStringAsFixed(1);

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(ch.icon, size: 15, color: ch.color),
                        const SizedBox(width: 6),
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
                      ],
                    ),
                    const SizedBox(height: 3),
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
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: AppColors.slateBg,
                        valueColor: AlwaysStoppedAnimation<Color>(ch.color),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
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
