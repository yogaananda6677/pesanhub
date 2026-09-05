import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import 'models/dashboard_state.dart';
import 'models/operational_summary.dart';
import 'widgets/freshness_indicator.dart';
import 'widgets/metric_card.dart';

/// DashboardView renders the operational overview for the cashier/cook.
/// Fulfills Issue #25 Acceptance Criteria #1, #2, #3, and #4.
class DashboardView extends StatelessWidget {
  final DashboardState state;
  final VoidCallback? onRefresh;
  final VoidCallback? onNavigateToPos;
  final VoidCallback? onNavigateToQueue;
  final VoidCallback? onNavigateToKds;

  const DashboardView({
    super.key,
    required this.state,
    this.onRefresh,
    this.onNavigateToPos,
    this.onNavigateToQueue,
    this.onNavigateToKds,
  });

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

        return SingleChildScrollView(
          key: const PageStorageKey('cashier_dashboard_scroll'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FreshnessIndicator(summary: summary, onRefresh: onRefresh),
              const SizedBox(height: AppSpacing.md),
              _buildQuickActionBar(context),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Status Antrean Operasional',
                style: AppTypography.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              GridView.builder(
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
                    subtitle: 'Di dapur KDS',
                    onTap: onNavigateToKds,
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionBar(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aksi Cepat Kasir', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Lanjutkan alur kerja operasional dalam satu ketukan.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Buat Pesanan Baru',
                  icon: Icons.add_circle_outline_rounded,
                  onPressed: onNavigateToPos,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton.secondary(
                  label: 'Lihat Dapur KDS',
                  icon: Icons.outdoor_grill_rounded,
                  onPressed: onNavigateToKds,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
