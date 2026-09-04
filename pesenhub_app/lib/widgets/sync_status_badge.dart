import 'package:flutter/material.dart';
import '../data/sync/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// SyncStatusBadge renders reactive synchronization status in headers and toolbars.
/// Fulfills Issue #33 Acceptance Criteria #5.
class SyncStatusBadge extends StatelessWidget {
  final SyncServiceState state;
  final VoidCallback? onTriggerSync;
  final VoidCallback? onViewErrors;

  const SyncStatusBadge({
    super.key,
    required this.state,
    this.onTriggerSync,
    this.onViewErrors,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isSyncing) {
      return Container(
        key: const Key('sync-status-syncing'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.infoBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.info.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.info),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Menyinkronkan ${state.pendingCount > 0 ? "(${state.pendingCount})" : ""}...',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (state.permanentFailureCount > 0) {
      return InkWell(
        key: const Key('sync-status-error'),
        onTap: onViewErrors,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withAlpha(100)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 14,
                color: AppColors.error,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${state.permanentFailureCount} Gagal Validasi',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.pendingCount > 0) {
      return InkWell(
        key: const Key('sync-status-pending'),
        onTap: onTriggerSync,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.warningBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.warning.withAlpha(80)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_queue_rounded,
                size: 14,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${state.pendingCount} Offline Antre',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Fully synced / idle state
    return Container(
      key: const Key('sync-status-idle'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_done_rounded,
            size: 14,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Tersinkron',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
