import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// AppCard provides a consistent surface container for order cards, summary metrics,
/// and kitchen queue items.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final BorderSide? borderSide;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.backgroundColor = AppColors.surface,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: AppSpacing.borderRadiusMd,
      side: borderSide ?? const BorderSide(color: AppColors.border, width: 1),
    );

    if (onTap != null) {
      return Material(
        color: backgroundColor,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.borderRadiusMd,
          child: Padding(padding: padding, child: child),
        ),
      );
    }

    return Material(
      color: backgroundColor,
      shape: shape,
      child: Padding(padding: padding, child: child),
    );
  }
}
