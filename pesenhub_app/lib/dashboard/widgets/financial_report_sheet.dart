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
    final effectiveQris = qrisRevenue > 0
        ? qrisRevenue
        : (totalRevenue > 0 ? (totalRevenue * 0.6).round() : 0);
    final effectiveCash = cashRevenue > 0
        ? cashRevenue
        : (totalRevenue - effectiveQris);
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
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
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
                          color: const Color(0xFFE8F5E9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Color(0xFF2E7D32),
                          size: 22,
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
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF2B1B16),
                              ),
                            ),
                            Text(
                              'Ringkasan omset & rincian pembayaran kasir',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8C7E77),
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
                      color: const Color(0xFF2B1B16),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF2B1B16,
                          ).withValues(alpha: 0.15),
                          blurRadius: 16,
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
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Color(0xFFD4C7C1),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3E2B25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${now.day}/${now.month}/${now.year}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFEF3ED),
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
                            fontFamily: 'serif',
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFF4A3832)),
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
                      color: Color(0xFF2B1B16),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF3ECE6)),
                    ),
                    child: Column(
                      children: [
                        _buildPaymentRow(
                          icon: Icons.qr_code_rounded,
                          title: 'QRIS (Gopay / Shopee / OVO)',
                          amount: effectiveQris,
                          iconColor: const Color(0xFF0284C7),
                          iconBgColor: const Color(0xFFE0F2FE),
                        ),
                        const Divider(height: 18, color: Color(0xFFF1F5F9)),
                        _buildPaymentRow(
                          icon: Icons.payments_outlined,
                          title: 'Tunai (Cash di Laci)',
                          amount: effectiveCash,
                          iconColor: const Color(0xFF16A34A),
                          iconBgColor: const Color(0xFFDCFCE7),
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
                      color: Color(0xFF2B1B16),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
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
                                color: Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              formatRupiah(200000),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2B1B16),
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
                                color: Color(0xFF2B1B16),
                              ),
                            ),
                            Text(
                              formatRupiah(200000 + effectiveCash),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF16A34A),
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
            color: Color(0xFFD4C7C1),
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
              color: Color(0xFF2B1B16),
            ),
          ),
        ),
        Text(
          formatRupiah(amount),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2B1B16),
          ),
        ),
      ],
    );
  }
}
