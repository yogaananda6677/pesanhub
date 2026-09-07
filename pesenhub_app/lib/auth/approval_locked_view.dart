import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import 'session.dart';

class ApprovalLockedView extends StatelessWidget {
  final SessionController controller;

  const ApprovalLockedView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final (title, message, icon, color) = switch (status) {
      SessionStatus.rejected => (
        'Akses belum disetujui',
        'Permintaan akun ditolak. Hubungi Superadmin jika keputusan ini perlu ditinjau.',
        Icons.block_rounded,
        AppColors.error,
      ),
      SessionStatus.suspended => (
        'Akun ditangguhkan',
        'Seluruh fitur dinonaktifkan. Hubungi Superadmin untuk memulihkan akses.',
        Icons.gpp_bad_rounded,
        AppColors.error,
      ),
      SessionStatus.offlineLocked => (
        'Status belum dapat diperiksa',
        'Sambungkan perangkat ke backend untuk memverifikasi persetujuan akun.',
        Icons.cloud_off_rounded,
        AppColors.warning,
      ),
      SessionStatus.webOnly => (
        'Superadmin hanya tersedia di web',
        'Akun ini tidak dapat membuka aplikasi operasional Owner. Gunakan portal web Superadmin.',
        Icons.language_rounded,
        AppColors.info,
      ),
      _ => (
        'Menunggu persetujuan Superadmin',
        'Akun Google sudah terverifikasi. Fitur PesenHub tetap terkunci sampai Superadmin menyetujui akses.',
        Icons.lock_rounded,
        AppColors.warning,
      ),
    };
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AppCard(
                child: Column(
                  children: [
                    Semantics(
                      label: title,
                      child: Icon(icon, size: 64, color: color),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.headline,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (controller.user case final user?) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        user.email,
                        style: AppTypography.labelLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (controller.errorMessage case final error?) ...[
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: 'Cek status lagi',
                      icon: Icons.refresh_rounded,
                      isFullWidth: true,
                      onPressed: controller.refreshApproval,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton.outlined(
                      label: 'Keluar',
                      icon: Icons.logout_rounded,
                      isFullWidth: true,
                      onPressed: controller.signOut,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
