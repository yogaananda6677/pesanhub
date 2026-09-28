import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// AppLoadingState displays an accessible progress indicator and status label.
class AppLoadingState extends StatelessWidget {
  final String message;

  const AppLoadingState({super.key, this.message = 'Memuat data...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// AppEmptyState displays a friendly empty-queue or empty-list state.
class AppEmptyState extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    this.title = 'Belum Ada Data',
    this.description = 'Data yang baru dibuat akan muncul di sini.',
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              description,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// AppErrorState displays actionable error feedback with a retry option.
class AppErrorState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppErrorState({
    super.key,
    this.title = 'Gagal Memuat Data',
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.onRetry,
    this.retryLabel = 'Coba Lagi',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.errorBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTypography.titleLarge.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum AppBannerType { info, success, warning, error }

/// Consistent transient feedback for create, update, payment, and status actions.
/// Every variant combines icon, title, message, and semantic announcement so
/// meaning never depends on color alone.
abstract final class AppFeedback {
  static const Duration displayDuration = Duration(seconds: 1);
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context, {
    required String message,
    AppBannerType type = AppBannerType.info,
  }) {
    final visual = _visualFor(type);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    _dismiss();
    _activeEntry = OverlayEntry(
      builder: (overlayContext) {
        final topPadding = MediaQuery.paddingOf(overlayContext).top;
        return _TimedFeedback(
          duration: displayDuration,
          onDismiss: _dismiss,
          child: Positioned(
            top: topPadding + AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  key: Key('app-feedback-${type.name}'),
                  color: visual.background,
                  elevation: 8,
                  borderRadius: AppSpacing.borderRadiusMd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Semantics(
                      key: const Key('app-feedback-live-region'),
                      liveRegion: true,
                      excludeSemantics: true,
                      label: '${visual.title}. $message',
                      child: Row(
                        children: [
                          Icon(visual.icon, color: visual.foreground),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  visual.title,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: visual.foreground,
                                  ),
                                ),
                                Text(
                                  message,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: visual.foreground,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tutup alert',
                            visualDensity: VisualDensity.compact,
                            onPressed: _dismiss,
                            icon: Icon(
                              Icons.close_rounded,
                              color: visual.foreground,
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
      },
    );
    overlay.insert(_activeEntry!);
  }

  static void _dismiss() {
    final entry = _activeEntry;
    _activeEntry = null;
    if (entry?.mounted ?? false) entry!.remove();
  }

  static _FeedbackVisual _visualFor(AppBannerType type) {
    return switch (type) {
      AppBannerType.success => const _FeedbackVisual(
        title: 'Berhasil diperbarui',
        icon: Icons.check_circle_outline_rounded,
        foreground: AppColors.success,
        background: AppColors.successBg,
      ),
      AppBannerType.info => const _FeedbackVisual(
        title: 'Informasi',
        icon: Icons.info_outline_rounded,
        foreground: AppColors.info,
        background: AppColors.infoBg,
      ),
      AppBannerType.warning => const _FeedbackVisual(
        title: 'Perlu perhatian',
        icon: Icons.warning_amber_rounded,
        foreground: AppColors.warning,
        background: AppColors.warningBg,
      ),
      AppBannerType.error => const _FeedbackVisual(
        title: 'Pembaruan gagal',
        icon: Icons.error_outline_rounded,
        foreground: AppColors.error,
        background: AppColors.errorBg,
      ),
    };
  }
}

class _TimedFeedback extends StatefulWidget {
  final Duration duration;
  final VoidCallback onDismiss;
  final Widget child;

  const _TimedFeedback({
    required this.duration,
    required this.onDismiss,
    required this.child,
  });

  @override
  State<_TimedFeedback> createState() => _TimedFeedbackState();
}

class _TimedFeedbackState extends State<_TimedFeedback> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FeedbackVisual {
  final String title;
  final IconData icon;
  final Color foreground;
  final Color background;

  const _FeedbackVisual({
    required this.title,
    required this.icon,
    required this.foreground,
    required this.background,
  });
}

/// AppBanner displays contextual alert messages within views.
class AppBanner extends StatelessWidget {
  final String message;
  final AppBannerType type;
  final VoidCallback? onClose;

  const AppBanner({
    super.key,
    required this.message,
    this.type = AppBannerType.info,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (type) {
      case AppBannerType.info:
        bg = AppColors.infoBg;
        fg = AppColors.info;
        icon = Icons.info_outline_rounded;
        break;
      case AppBannerType.success:
        bg = AppColors.successBg;
        fg = AppColors.success;
        icon = Icons.check_circle_outline_rounded;
        break;
      case AppBannerType.warning:
        bg = AppColors.warningBg;
        fg = AppColors.warning;
        icon = Icons.warning_amber_rounded;
        break;
      case AppBannerType.error:
        bg = AppColors.errorBg;
        fg = AppColors.error;
        icon = Icons.error_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: fg),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}
