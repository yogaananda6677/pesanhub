import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_feedback.dart';
import '../models/operational_summary.dart';

/// FreshnessIndicator displays the operational snapshot freshness and sync alert.
class FreshnessIndicator extends StatelessWidget {
  final OperationalSummary summary;
  final VoidCallback? onRefresh;

  const FreshnessIndicator({super.key, required this.summary, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.isOffline) ...[
          const AppBanner(
            message:
                'Mode Offline: Menggunakan data lokal. Pesanan baru akan disimpan di outbox.',
            type: AppBannerType.warning,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else if (summary.isStale) ...[
          const AppBanner(
            message:
                'Data Usang: Sambungan ke server belum diperbarui. Ketuk refresh untuk memperbarui.',
            type: AppBannerType.warning,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final shouldStack = constraints.maxWidth < 520 || textScale > 1.3;
            final freshness = Row(
              children: [
                Icon(
                  summary.isOffline
                      ? Icons.cloud_off_rounded
                      : (summary.isStale
                            ? Icons.sync_problem_rounded
                            : Icons.sync_rounded),
                  size: 16,
                  color: summary.isOffline
                      ? AppColors.warning
                      : (summary.isStale
                            ? AppColors.warning
                            : AppColors.textSecondary),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    summary.isOffline
                        ? 'Offline • Terakhir: ${summary.formattedTime}'
                        : 'Terakhir diperbarui: ${summary.formattedTime}',
                    style: AppTypography.bodySmall.copyWith(
                      color: summary.isOffline || summary.isStale
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            );
            final actions = Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              children: [
                if (summary.pendingSyncCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: AppSpacing.borderRadiusFull,
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${summary.pendingSyncCount} antrean offline',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Segarkan data operasional',
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    onPressed: onRefresh,
                  ),
              ],
            );

            if (shouldStack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [freshness, const SizedBox(height: 2), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: freshness),
                const SizedBox(width: AppSpacing.sm),
                actions,
              ],
            );
          },
        ),
      ],
    );
  }
}
