import 'package:flutter/material.dart';
import '../connectivity/connectivity_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

class ConnectivityBadge extends StatelessWidget {
  final ConnectivityController controller;
  final VoidCallback? onReviewErrors;
  const ConnectivityBadge({
    super.key,
    required this.controller,
    this.onReviewErrors,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      final offline = state == OperationalConnectionState.offline;
      final syncing = state == OperationalConnectionState.syncing;
      final degraded = state == OperationalConnectionState.degraded;
      final expired = state == OperationalConnectionState.sessionExpired;
      final label = switch (state) {
        OperationalConnectionState.offline =>
          controller.pendingCount > 0
              ? 'Offline • ${controller.pendingCount}'
              : 'Offline',
        OperationalConnectionState.syncing =>
          controller.pendingCount > 0
              ? 'Sinkron • ${controller.pendingCount}'
              : 'Sinkron',
        OperationalConnectionState.degraded => 'Gangguan',
        OperationalConnectionState.sessionExpired => 'Sesi habis',
        OperationalConnectionState.online => 'Online',
      };
      final color = offline || expired
          ? AppColors.error
          : syncing || degraded
          ? AppColors.warning
          : AppColors.success;
      final bg = offline || expired
          ? AppColors.errorBg
          : syncing || degraded
          ? AppColors.warningBg
          : AppColors.successBg;
      final icon = expired
          ? Icons.lock_clock_rounded
          : offline
          ? Icons.cloud_off_rounded
          : syncing
          ? Icons.sync_rounded
          : degraded
          ? Icons.cloud_sync_rounded
          : Icons.cloud_done_rounded;
      final semantic = StringBuffer('Status koneksi backend: $label');
      if (controller.pendingCount > 0) {
        semantic.write(', ${controller.pendingCount} menunggu sinkron');
      }
      if (controller.permanentFailureCount > 0) {
        semantic.write(
          ', ${controller.permanentFailureCount} perlu diperbaiki',
        );
      }
      return Semantics(
        label: semantic.toString(),
        button: true,
        liveRegion: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showDetails(context),
            borderRadius: AppSpacing.borderRadiusFull,
            child: Container(
              key: Key('connectivity-${state.name}'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppSpacing.borderRadiusFull,
                border: Border.all(color: color.withValues(alpha: .35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _showDetails(BuildContext context) async {
    final state = controller.state;
    final lastSync = controller.lastSuccessfulSyncAt;
    final time = lastSync == null
        ? 'Belum pernah'
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(lastSync.toLocal()),
            alwaysUse24HourFormat: true,
          );
    final retryAt = controller.nextRetryAt;
    final retryTime = retryAt == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(retryAt.toLocal()),
            alwaysUse24HourFormat: true,
          );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            key: const Key('connectivity-detail-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Status Sinkronisasi',
                style: AppTypography.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Backend: ${_stateLabel(state)}',
                style: AppTypography.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Menunggu sinkron: ${controller.pendingCount}',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('Terakhir sinkron: $time', style: AppTypography.bodyMedium),
              if (controller.retryAttempt > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Percobaan koneksi: ${controller.retryAttempt}',
                  style: AppTypography.bodyMedium,
                ),
              ],
              if (retryTime != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Coba otomatis berikutnya: $retryTime',
                  style: AppTypography.bodyMedium,
                ),
              ],
              if (controller.permanentFailureCount > 0) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${controller.permanentFailureCount} pesanan perlu dikoreksi sebelum dapat dikirim.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (state != OperationalConnectionState.sessionExpired)
                AppButton(
                  label: 'Coba Sinkronkan',
                  icon: Icons.sync_rounded,
                  isFullWidth: true,
                  onPressed: () {
                    Navigator.pop(context);
                    controller.requestRetry();
                  },
                ),
              if (controller.permanentFailureCount > 0 &&
                  onReviewErrors != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton.outlined(
                  label: 'Koreksi di Kasir',
                  icon: Icons.edit_note_rounded,
                  isFullWidth: true,
                  onPressed: () {
                    Navigator.pop(context);
                    onReviewErrors?.call();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _stateLabel(OperationalConnectionState state) => switch (state) {
    OperationalConnectionState.online => 'Online',
    OperationalConnectionState.offline => 'Offline — data lokal tetap tersedia',
    OperationalConnectionState.syncing => 'Menyinkronkan',
    OperationalConnectionState.degraded => 'Gangguan layanan',
    OperationalConnectionState.sessionExpired => 'Sesi berakhir',
  };
}
