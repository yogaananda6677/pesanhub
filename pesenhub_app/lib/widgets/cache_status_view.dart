import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// Status state of the local cache.
enum CacheViewStatus { loading, success, stale, empty, error }

/// CacheStatusView displays comprehensive cache states (Loading, Success, Stale, Empty, Error)
/// for local database cold start and offline operations on mobile and tablet.
/// Fulfills Issue #32 Acceptance Criteria #2 and #5.
class CacheStatusView extends StatelessWidget {
  final CacheViewStatus status;
  final String? cachedAtFormatted;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;
  final Widget? child;

  const CacheStatusView({
    super.key,
    required this.status,
    this.cachedAtFormatted,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case CacheViewStatus.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  'Memuat data dari database lokal...',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
        );

      case CacheViewStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  errorMessage ?? 'Gagal membaca database lokal',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Coba Lagi',
                    variant: AppButtonVariant.primary,
                    icon: Icons.refresh_rounded,
                    onPressed: onRetry,
                  ),
                ],
              ],
            ),
          ),
        );

      case CacheViewStatus.empty:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storage_rounded,
                  size: 48,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Database Lokal Kosong',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Belum ada data katalog atau pesanan tersimpan di perangkat ini.',
                  style: AppTypography.bodySmall,
                  textAlign: TextAlign.center,
                ),
                if (onRefresh != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Sinkronkan Sekarang',
                    variant: AppButtonVariant.primary,
                    icon: Icons.cloud_download_rounded,
                    onPressed: onRefresh,
                  ),
                ],
              ],
            ),
          ),
        );

      case CacheViewStatus.stale:
        final timeText = cachedAtFormatted != null
            ? ' (Terakhir disimpan: $cachedAtFormatted)'
            : '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('stale-cache-banner'),
              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Mode Offline: Menampilkan data cache lokal$timeText.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onRefresh != null)
                    IconButton(
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: AppColors.warning,
                      ),
                      onPressed: onRefresh,
                      tooltip: 'Perbarui Data',
                    ),
                ],
              ),
            ),
            if (child != null) Expanded(child: child!),
          ],
        );

      case CacheViewStatus.success:
        if (child != null) return child!;
        return const SizedBox.shrink();
    }
  }
}
