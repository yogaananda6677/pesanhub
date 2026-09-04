import 'package:flutter/material.dart';
import '../connectivity/connectivity_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class ConnectivityBadge extends StatelessWidget {
  final ConnectivityController controller;
  const ConnectivityBadge({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      final offline = state == OperationalConnectionState.offline;
      final syncing = state == OperationalConnectionState.syncing;
      final label = offline
          ? 'Offline'
          : syncing
          ? 'Menyinkronkan'
          : 'Online';
      final color = offline
          ? AppColors.error
          : syncing
          ? AppColors.warning
          : AppColors.success;
      final bg = offline
          ? AppColors.errorBg
          : syncing
          ? AppColors.warningBg
          : AppColors.successBg;
      final icon = offline
          ? Icons.cloud_off_rounded
          : syncing
          ? Icons.sync_rounded
          : Icons.cloud_done_rounded;
      return Semantics(
        label: 'Status koneksi: $label',
        liveRegion: true,
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
      );
    },
  );
}
