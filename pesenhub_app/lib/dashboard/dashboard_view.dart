import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_feedback.dart';
import 'models/dashboard_state.dart';
import 'models/operational_summary.dart';
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

              // 2. Aksi Cepat Section
              _buildQuickActionsSection(summary),
              const SizedBox(height: AppSpacing.lg),

              // 3. Status Antrean Section
              _buildQueueStatusSection(summary),
              const SizedBox(height: AppSpacing.xl),

              // Catalog management is visible only when an authorized role
              // supplies the navigation callback.
              if (onNavigateToMenu != null) ...[
                _buildMenuSection(),
                const SizedBox(height: AppSpacing.xl),
              ],

              // 4. Detailed Operational Metrics
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
            '${getGreeting(now)}, ${name.toUpperCase()} 👋',
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
                    fontSize: 23,
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
            'Semangat jualan hari ini!',
            style: TextStyle(fontSize: 13, color: Color(0xFF8C7E77)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(OperationalSummary summary) {
    final activeTickets = summary.activeOrdersCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AKSI CEPAT',
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
                title: 'Buat\nPesanan',
                subtitle: 'Create order',
                icon: Icons.add_rounded,
                iconColor: const Color(0xFFC62828),
                iconBgColor: const Color(0xFFFDE8E4),
                contractActionLabel: 'Buat Pesanan Baru',
                onTap: onNavigateToPos,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _QuickActionCard(
                title: 'Antrean\nDapur',
                subtitle: '$activeTickets Tiket',
                subtitleColor: const Color(0xFFC62828),
                icon: Icons.format_list_bulleted_rounded,
                iconColor: const Color(0xFF3E2723),
                iconBgColor: const Color(0xFFF5EDE4),
                contractActionLabel: 'Lihat Antrean',
                onTap: onNavigateToQueue ?? onNavigateToKds,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (onNavigateToMenu != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  title: 'Kasir POS',
                  subtitle: 'POS cashier',
                  icon: Icons.point_of_sale_rounded,
                  iconColor: const Color(0xFF2B1B16),
                  iconBgColor: const Color(0xFFF0ECE9),
                  onTap: onNavigateToPos,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _QuickActionCard(
                  title: 'Menu &\nHarga',
                  subtitle: 'Menu & prices',
                  icon: Icons.lock_outline_rounded,
                  iconColor: const Color(0xFF2B1B16),
                  iconBgColor: const Color(0xFFF5EDE4),
                  onTap: onNavigateToMenu,
                ),
              ),
            ],
          ),
        ],
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

  Widget _buildMenuSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Menu & Harga',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            fontFamily: 'serif',
            color: Color(0xFF2B1B16),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MenuActionCard(
          title: 'Kelola Menu',
          subtitle: 'Manage menu items',
          icon: Icons.lock_outline_rounded,
          iconBgColor: const Color(0xFFF5EDE4),
          iconColor: const Color(0xFF2B1B16),
          onTap: onNavigateToMenu,
        ),
        const SizedBox(height: AppSpacing.sm),
        _MenuActionCard(
          title: 'Kelola Harga',
          subtitle: 'Manage prices & modifiers',
          icon: Icons.local_offer_outlined,
          iconBgColor: const Color(0xFFFDE8E4),
          iconColor: const Color(0xFFC62828),
          onTap: onNavigateToMenu,
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
          title: 'Pesanan Terlambat',
          count: summary.overdueCount,
          icon: Icons.timer_off_rounded,
          accentColor: AppColors.error,
          subtitle: '> 15 menit belum selesai',
          isAlert: summary.overdueCount > 0,
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

class _MenuActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final VoidCallback? onTap;

  const _MenuActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF3ECE6)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2B1B16).withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
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
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2B1B16),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8C7E77),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF8C7E77),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
