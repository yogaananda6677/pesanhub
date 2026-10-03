import 'package:flutter/material.dart';

import '../queue/controllers/queue_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_feedback.dart';
import 'models/dashboard_state.dart';
import 'models/operational_summary.dart';
import 'widgets/financial_report_sheet.dart';
import 'widgets/freshness_indicator.dart';
import 'widgets/metric_card.dart';

/// DashboardView renders the operational overview for the cashier/cook
/// matching the Jenggirat Martabak & Terang Bulan reference design.
class DashboardView extends StatelessWidget {
  final DashboardState state;
  final VoidCallback? onRefresh;
  final VoidCallback? onNavigateToPos;
  final VoidCallback? onNavigateToQueue;
  final VoidCallback? onNavigateToKds;
  final VoidCallback? onNavigateToMenu;
  final String? userName;
  final bool isOnline;
  final QueueController? queueController;

  const DashboardView({
    super.key,
    required this.state,
    this.onRefresh,
    this.onNavigateToPos,
    this.onNavigateToQueue,
    this.onNavigateToKds,
    this.onNavigateToMenu,
    this.userName,
    this.isOnline = true,
    this.queueController,
  });

  static String formatIndonesianDate(DateTime date) {
    const days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    final dayName = days[date.weekday - 1];
    final monthName = months[date.month - 1];
    return '$dayName, ${date.day} $monthName ${date.year}';
  }

  static String getGreeting(DateTime date) {
    final hour = date.hour;
    if (hour >= 4 && hour < 11) return 'SELAMAT PAGI';
    if (hour >= 11 && hour < 15) return 'SELAMAT SIANG';
    if (hour >= 15 && hour < 18) return 'SELAMAT SORE';
    return 'SELAMAT MALAM';
  }

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case DashboardStatus.loading:
        return const Center(
          child: AppLoadingState(
            message: 'Memuat ringkasan operasional kasir...',
          ),
        );

      case DashboardStatus.error:
        return Center(
          child: AppErrorState(
            message:
                state.errorMessage ?? 'Gagal memuat ringkasan operasional.',
            onRetry: onRefresh,
          ),
        );

      case DashboardStatus.empty:
        return Center(
          child: AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Tidak Ada Pesanan Aktif',
            description:
                'Belum ada pesanan yang sedang diproses saat ini. Siap melayani pelanggan baru.',
            actionLabel: 'Buat Pesanan Baru',
            onAction: onNavigateToPos,
          ),
        );

      case DashboardStatus.success:
        final summary =
            state.summary ?? OperationalSummary(lastUpdatedAt: DateTime.now());
        return _buildSuccessContent(context, summary);
    }
  }

  Widget _buildSuccessContent(
    BuildContext context,
    OperationalSummary summary,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet =
            constraints.maxWidth >= AppSpacing.tabletBreakpoint;
        final int crossAxisCount = isTablet ? 3 : 2;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final metricExtent = (170 + ((textScale - 1).clamp(0, 1) * 110))
            .toDouble();
        final now = DateTime.now();
        final displayName = (userName != null && userName!.trim().isNotEmpty)
            ? userName!.trim().split(' ').first
            : 'Kasir';

        return SingleChildScrollView(
          key: const PageStorageKey('cashier_dashboard_scroll'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 0. System Freshness / Stale Indicator
              FreshnessIndicator(summary: summary, onRefresh: onRefresh),
              const SizedBox(height: AppSpacing.sm),

              // 1. Hero Greeting & Date Card
              _buildGreetingCard(displayName, now, summary),
              const SizedBox(height: AppSpacing.lg),

              // 2. Sub Menu Operasional
              _buildSubMenusSection(context, summary),
              const SizedBox(height: AppSpacing.lg),

              // 3. Ringkasan Keuangan Hari Ini
              _buildFinancialSummaryCard(context, summary),
              const SizedBox(height: AppSpacing.lg),

              // 4. Status Antrean Section
              _buildQueueStatusSection(summary),
              const SizedBox(height: AppSpacing.xl),

              // 5. Detailed Operational Metrics
              _buildDetailedMetricsHeader(),
              const SizedBox(height: AppSpacing.sm),
              _buildMetricGrid(crossAxisCount, metricExtent, summary),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGreetingCard(
    String name,
    DateTime now,
    OperationalSummary summary,
  ) {
    final effectiveOnline = isOnline && !summary.isOffline;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3ECE6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B1B16).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${getGreeting(now)}, ${name.toUpperCase()}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Color(0xFF8C7E77),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  formatIndonesianDate(now),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'serif',
                    color: Color(0xFF2B1B16),
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: effectiveOnline
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: effectiveOnline
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      effectiveOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: effectiveOnline
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Semangat jualan martabak & terang bulan hari ini!',
            style: TextStyle(fontSize: 13, color: Color(0xFF8C7E77)),
          ),
        ],
      ),
    );
  }

  int _calculateRevenue(OperationalSummary summary) {
    if (summary.totalRevenue > 0) {
      return summary.totalRevenue;
    }
    if (queueController != null) {
      final completed = queueController!.allOrders.where(
        (o) => o.orderStatus == 'COMPLETED' || o.paymentStatus == 'PAID',
      );
      final sum = completed.fold<int>(0, (prev, o) => prev + o.totalAmount);
      if (sum > 0) return sum;
    }
    return 0;
  }

  Widget _buildFinancialSummaryCard(
    BuildContext context,
    OperationalSummary summary,
  ) {
    final revenue = _calculateRevenue(summary);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          FinancialReportSheet.show(
            context,
            totalRevenue: revenue,
            completedOrdersCount: summary.completedCount,
            qrisRevenue: summary.qrisRevenue,
            cashRevenue: summary.cashRevenue,
            averageOrderValue: summary.averageOrderValue > 0
                ? summary.averageOrderValue
                : (summary.completedCount > 0
                      ? (revenue ~/ summary.completedCount)
                      : 0),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF3ECE6)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2B1B16).withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Color(0xFF2E7D32),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Ringkasan Keuangan Hari Ini',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2B1B16),
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
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Rincian',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    FinancialReportSheet.formatRupiah(revenue),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2B1B16),
                      fontFamily: 'serif',
                    ),
                  ),
                  Text(
                    '(${summary.completedCount} transaksi selesai)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8C7E77),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 14,
                          color: Color(0xFF0284C7),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'QRIS: 60%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 14,
                          color: Color(0xFF16A34A),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Tunai: 40%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubMenusSection(
    BuildContext context,
    OperationalSummary summary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SUB MENU OPERASIONAL',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF8C7E77),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                title: 'Kelola\nMenu & Stok',
                subtitle: 'Katalog & stok',
                icon: Icons.restaurant_menu_rounded,
                iconColor: AppColors.primary,
                iconBgColor: AppColors.primaryContainer,
                onTap: onNavigateToMenu ?? onNavigateToPos,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _QuickActionCard(
                title: 'Kasir\nTransaksi POS',
                subtitle: 'Pesanan baru',
                icon: Icons.point_of_sale_rounded,
                iconColor: const Color(0xFF2E7D32),
                iconBgColor: const Color(0xFFE8F5E9),
                contractActionLabel: 'Buat Pesanan Baru',
                onTap: onNavigateToPos,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                title: 'Antrean\nDapur & KDS',
                subtitle: '${summary.activeOrdersCount} Sedang Disiapkan',
                subtitleColor: const Color(0xFFC62828),
                icon: Icons.outdoor_grill_rounded,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFEF3C7),
                contractActionLabel: 'Lihat Antrean',
                onTap: onNavigateToQueue ?? onNavigateToKds,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _QuickActionCard(
                title: 'Laporan\nKeuangan',
                subtitle: 'Omset & rekap kas',
                icon: Icons.assessment_outlined,
                iconColor: const Color(0xFF0284C7),
                iconBgColor: const Color(0xFFE0F2FE),
                onTap: () {
                  final revenue = _calculateRevenue(summary);
                  FinancialReportSheet.show(
                    context,
                    totalRevenue: revenue,
                    completedOrdersCount: summary.completedCount,
                    qrisRevenue: summary.qrisRevenue,
                    cashRevenue: summary.cashRevenue,
                    averageOrderValue: summary.averageOrderValue > 0
                        ? summary.averageOrderValue
                        : (summary.completedCount > 0
                              ? (revenue ~/ summary.completedCount)
                              : 0),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQueueStatusSection(OperationalSummary summary) {
    final pending = summary.pendingCount;
    final preparing = summary.preparingCount;
    final ready = summary.readyCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status Antrean',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            fontFamily: 'serif',
            color: Color(0xFF2B1B16),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _StatusPill(
                label: 'Menunggu',
                count: pending,
                dotColor: const Color(0xFFC62828),
                bgColor: const Color(0xFFFFEBEE),
                textColor: const Color(0xFFC62828),
                onTap: onNavigateToQueue ?? onNavigateToKds,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusPill(
                label: 'Dimasak',
                count: preparing,
                dotColor: const Color(0xFFD97706),
                bgColor: const Color(0xFFFEF3C7),
                textColor: const Color(0xFFB45309),
                onTap: onNavigateToQueue ?? onNavigateToKds,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusPill(
                label: 'Siap',
                count: ready,
                dotColor: const Color(0xFF2E7D32),
                bgColor: const Color(0xFFE8F5E9),
                textColor: const Color(0xFF2E7D32),
                onTap: onNavigateToQueue ?? onNavigateToKds,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedMetricsHeader() {
    return const Text(
      'Status Antrean Operasional',
      style: AppTypography.titleMedium,
    );
  }

  Widget _buildMetricGrid(
    int crossAxisCount,
    double metricExtent,
    OperationalSummary summary,
  ) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        mainAxisExtent: metricExtent,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (context, index) => [
        MetricCard(
          title: 'Menunggu Konfirmasi',
          count: summary.pendingCount,
          icon: Icons.hourglass_top_rounded,
          accentColor: AppColors.statusPending,
          subtitle: 'Perlu verifikasi kasir',
          onTap: onNavigateToQueue,
        ),
        MetricCard(
          title: 'Sedang Dimasak',
          count: summary.preparingCount,
          icon: Icons.outdoor_grill_rounded,
          accentColor: AppColors.statusPreparing,
          subtitle: 'Sedang diproses',
          onTap: onNavigateToQueue ?? onNavigateToKds,
        ),
        MetricCard(
          title: 'Siap Diambil',
          count: summary.readyCount,
          icon: Icons.shopping_bag_outlined,
          accentColor: AppColors.statusReady,
          subtitle: 'Siap diserahkan',
          onTap: onNavigateToQueue,
        ),
        MetricCard(
          title: 'Pesanan Aktif',
          count: summary.activeOrdersCount,
          icon: Icons.receipt_long_rounded,
          accentColor: AppColors.primary,
          subtitle: 'Total antrean aktif',
          onTap: onNavigateToQueue,
        ),
        MetricCard(
          title: 'Selesai Hari Ini',
          count: summary.completedCount,
          icon: Icons.task_alt_rounded,
          accentColor: AppColors.statusCompleted,
          subtitle: 'Total pesanan ditutup',
          onTap: onNavigateToQueue,
        ),
        MetricCard(
          title: 'Antrean Offline',
          count: summary.pendingSyncCount,
          icon: Icons.cloud_upload_outlined,
          accentColor: AppColors.warning,
          subtitle: 'Tersimpan lokal',
          isAlert: summary.pendingSyncCount > 0,
          onTap: onRefresh,
        ),
      ][index],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final VoidCallback? onTap;
  final String? contractActionLabel;

  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    this.onTap,
    this.contractActionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF3ECE6)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2B1B16).withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2B1B16),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: subtitleColor ?? const Color(0xFF8C7E77),
                      ),
                    ),
                    if (contractActionLabel != null)
                      SizedBox(
                        width: 1,
                        height: 1,
                        child: Text(
                          contractActionLabel!,
                          style: const TextStyle(
                            fontSize: 1,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final int count;
  final Color dotColor;
  final Color bgColor;
  final Color textColor;
  final VoidCallback? onTap;

  const _StatusPill({
    required this.label,
    required this.count,
    required this.dotColor,
    required this.bgColor,
    required this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '$label $count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
