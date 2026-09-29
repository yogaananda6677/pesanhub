import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/brand_logo.dart';
import 'session.dart';

class LoginView extends StatefulWidget {
  final SessionController controller;
  const LoginView({super.key, required this.controller});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant LoginView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.status == SessionStatus.signingIn;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandLogo(size: 80)),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Masuk ke PesenHub',
                        textAlign: TextAlign.center,
                        style: AppTypography.headline,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Masuk sebagai Admin, atau gunakan akun Google yang diundang sebagai Kasir.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (widget.controller.errorMessage case final error?) ...[
                        const SizedBox(height: AppSpacing.lg),
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
                      AppButton.outlined(
                        label: 'Lanjutkan dengan Google',
                        icon: Icons.account_circle_outlined,
                        isFullWidth: true,
                        isLoading: busy,
                        onPressed: busy
                            ? null
                            : widget.controller.signInWithGoogle,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Google memverifikasi kepemilikan email. Role dan hak akses tetap ditentukan oleh backend PesenHub.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
