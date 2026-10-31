import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class FinancialReportSheet extends StatelessWidget {
  final int totalRevenue;
  final int completedOrdersCount;
  final int qrisRevenue;
  final int cashRevenue;
  final int averageOrderValue;
  final VoidCallback? onPrintSummary;

  const FinancialReportSheet({
    super.key,
    required this.totalRevenue,
    required this.completedOrdersCount,
    this.qrisRevenue = 0,
    this.cashRevenue = 0,
    this.averageOrderValue = 0,
    this.onPrintSummary,
  });

  static Future<void> show(
    BuildContext context, {
    required int totalRevenue,
    required int completedOrdersCount,
    int qrisRevenue = 0,
    int cashRevenue = 0,
    int averageOrderValue = 0,
    VoidCallback? onPrintSummary,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FinancialReportSheet(
        totalRevenue: totalRevenue,
        completedOrdersCount: completedOrdersCount,
        qrisRevenue: qrisRevenue,
        cashRevenue: cashRevenue,
        averageOrderValue: averageOrderValue,
        onPrintSummary: onPrintSummary,
      ),
    );
  }

  static String formatRupiah(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write('.');
      }
    }
    return 'Rp ${buffer.toString().split('').reversed.join()}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final effectiveQris = qrisRevenue;
    final effectiveCash = cashRevenue > 0
        ? cashRevenue
        : (totalRevenue >= qrisRevenue ? totalRevenue - qrisRevenue : 0);
    final effectiveAvg = averageOrderValue > 0
        ? averageOrderValue
        : (completedOrdersCount > 0
              ? (totalRevenue / completedOrdersCount).round()
              : 0);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.emeraldBorder),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: AppColors.emerald,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Laporan Keuangan Hari Ini',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: AppColors.obsidianDark,
                              ),
                            ),
                            Text(
                              'Ringkasan omset & rincian pembayaran kasir',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.neutralTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Total Revenue Hero Card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.obsidianDark,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.obsidianDark.withValues(alpha: 0.15),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL OMSET PENJUALAN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppColors.neutralTextMuted,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${now.day}/${now.month}/${now.year}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          formatRupiah(totalRevenue),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricItem(
                                label: 'Pesanan Selesai',
                                value: '$completedOrdersCount Transaksi',
                              ),
                            ),
                            Expanded(
                              child: _buildMetricItem(
                                label: 'Rata-rata Transaksi',
                                value: formatRupiah(effectiveAvg),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Breakdown Metode Pembayaran
                  const Text(
                    'Rincian Metode Pembayaran',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppColors.obsidianDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorderModern),
                    ),
                    child: Column(
                      children: [
                        _buildPaymentRow(
                          icon: Icons.qr_code_rounded,
                          title: 'QRIS (Gopay / Shopee / OVO)',
                          amount: effectiveQris,
                          iconColor: AppColors.indigo,
                          iconBgColor: AppColors.indigoBg,
                        ),
                        const Divider(
                          height: 18,
                          color: AppColors.outlineVariant,
                        ),
                        _buildPaymentRow(
                          icon: Icons.payments_outlined,
                          title: 'Tunai (Cash di Laci)',
                          amount: effectiveCash,
                          iconColor: AppColors.emerald,
                          iconBgColor: AppColors.emeraldBg,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Informasi Kasir & Laci Kas
                  const Text(
                    'Kas & Laci Kasir',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppColors.obsidianDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.slateBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorderModern),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Modal Awal Kasir',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.slate,
                              ),
                            ),
                            Text(
                              formatRupiah(200000),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Estimasi Total Tunai di Laci',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              formatRupiah(200000 + effectiveCash),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accentGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Print button
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mencetak rekap ringkasan kasir...'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                      onPrintSummary?.call();
                    },
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Cetak Rekap Struk Kasir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildMetricItem({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.terracottaBorder,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  static Widget _buildPaymentRow({
    required IconData icon,
    required String title,
    required int amount,
    required Color iconColor,
    required Color iconBgColor,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          formatRupiah(amount),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
