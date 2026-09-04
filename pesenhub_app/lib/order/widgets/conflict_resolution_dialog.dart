import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../models/order_conflict.dart';

/// ConflictResolutionDialog presents an interactive modal for resolving order state conflicts.
/// Fulfills Issue #34 Acceptance Criteria #1, #3, and #5.
class ConflictResolutionDialog extends StatelessWidget {
  final ConflictClassification classification;
  final ValueChanged<ResolutionStrategy> onResolve;
  final VoidCallback? onDismiss;

  const ConflictResolutionDialog({
    super.key,
    required this.classification,
    required this.onResolve,
    this.onDismiss,
  });

  static Future<void> show({
    required BuildContext context,
    required ConflictClassification classification,
    required ValueChanged<ResolutionStrategy> onResolve,
    VoidCallback? onDismiss,
  }) {
    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isTablet ? 560 : 380,
            maxHeight: 650,
          ),
          child: ConflictResolutionDialog(
            classification: classification,
            onResolve: (strategy) {
              Navigator.of(ctx).pop();
              onResolve(strategy);
            },
            onDismiss: () {
              Navigator.of(ctx).pop();
              if (onDismiss != null) onDismiss();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSafe = classification.isSafe;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with Icon & Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: isSafe
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : AppColors.error.withValues(alpha: 0.15),
                    borderRadius: AppSpacing.borderRadiusSm,
                  ),
                  child: Icon(
                    isSafe ? Icons.sync_problem_rounded : Icons.gavel_rounded,
                    color: isSafe ? AppColors.warning : AppColors.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSafe
                            ? 'Resolusi Konflik Data'
                            : 'Pembaruan Server Wajib (Server-Wins)',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        isSafe
                            ? 'Pilih versi data yang ingin disimpan'
                            : 'Data server mengambil alih status pesanan',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Reason Callout
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSafe ? AppColors.warningBg : AppColors.errorBg,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(
                  color: isSafe
                      ? AppColors.warning.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: isSafe ? AppColors.warning : AppColors.error,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      classification.reason,
                      style: AppTypography.bodySmall.copyWith(
                        color: isSafe ? AppColors.textPrimary : AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Comparison Cards
            Text(
              'Perbandingan Versi:',
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Local Version Card
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.phone_android_rounded, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Lokal (v${classification.localOrder.version})',
                              style: AppTypography.labelSmall.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Status: ${classification.localOrder.orderStatus}',
                          style: AppTypography.bodySmall,
                        ),
                        Text(
                          'Bayar: ${classification.localOrder.paymentStatus}',
                          style: AppTypography.bodySmall,
                        ),
                        if (classification.localOrder.takeawayNotes != null &&
                            classification
                                .localOrder
                                .takeawayNotes!
                                .isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Catatan: ${classification.localOrder.takeawayNotes}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),

                // Server Version Card
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_done_rounded, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Server (v${classification.serverOrder.version})',
                              style: AppTypography.labelSmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Status: ${classification.serverOrder.orderStatus}',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Bayar: ${classification.serverOrder.paymentStatus}',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (classification.serverOrder.takeawayNotes != null &&
                            classification
                                .serverOrder
                                .takeawayNotes!
                                .isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Catatan: ${classification.serverOrder.takeawayNotes}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Actions
            if (isSafe) ...[
              AppButton(
                label: 'Gunakan Versi Server',
                variant: AppButtonVariant.secondary,
                icon: Icons.cloud_download_outlined,
                onPressed: () => onResolve(ResolutionStrategy.serverWins),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                label: 'Pertahankan Perubahan Lokal',
                variant: AppButtonVariant.primary,
                icon: Icons.check_circle_outline,
                onPressed: () => onResolve(ResolutionStrategy.clientWins),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                label: 'Gabungkan Catatan',
                variant: AppButtonVariant.secondary,
                icon: Icons.merge_type_rounded,
                onPressed: () => onResolve(ResolutionStrategy.merge),
              ),
            ] else ...[
              AppButton(
                label: 'Muat Ulang Data Server',
                variant: AppButtonVariant.primary,
                icon: Icons.refresh_rounded,
                onPressed: () => onResolve(ResolutionStrategy.forceReload),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
