import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, outlined, danger }

/// AppButton implements a consistent button meeting the minimum 48px touch target.
/// Fulfills Acceptance Criteria #1.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.height = AppSpacing.minTouchTarget,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.height = AppSpacing.minTouchTarget,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outlined({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.height = AppSpacing.minTouchTarget,
  }) : variant = AppButtonVariant.outlined;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.height = AppSpacing.minTouchTarget,
  }) : variant = AppButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final bool isInteractive = onPressed != null && !isLoading;

    Color backgroundColor;
    Color foregroundColor;
    BorderSide? borderSide;

    switch (variant) {
      case AppButtonVariant.primary:
        backgroundColor = isInteractive
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: 0.5);
        foregroundColor = AppColors.onPrimary;
        break;
      case AppButtonVariant.secondary:
        backgroundColor = isInteractive
            ? AppColors.secondary
            : AppColors.secondary.withValues(alpha: 0.5);
        foregroundColor = AppColors.onSecondary;
        break;
      case AppButtonVariant.outlined:
        backgroundColor = Colors.transparent;
        foregroundColor = isInteractive
            ? AppColors.textPrimary
            : AppColors.textMuted;
        borderSide = BorderSide(
          color: isInteractive
              ? AppColors.border
              : AppColors.border.withValues(alpha: 0.5),
          width: 1.5,
        );
        break;
      case AppButtonVariant.danger:
        backgroundColor = isInteractive
            ? AppColors.error
            : AppColors.error.withValues(alpha: 0.5);
        foregroundColor = AppColors.onPrimary;
        break;
    }

    Widget content;
    if (isLoading) {
      content = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
        ),
      );
    } else {
      content = Row(
        mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: foregroundColor),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(color: foregroundColor),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      );
    }

    final buttonWidget = Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusSm,
        side: borderSide ?? BorderSide.none,
      ),
      child: InkWell(
        onTap: isInteractive ? onPressed : null,
        borderRadius: AppSpacing.borderRadiusSm,
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: buttonWidget);
    }

    return buttonWidget;
  }
}
