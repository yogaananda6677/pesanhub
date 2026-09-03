import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';

/// ResponsiveLayout adapts UI structure between mobile (< 600dp) and tablet (>= 600dp) form factors.
/// Fulfills Acceptance Criteria #4.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.tablet,
  });

  /// Check whether the viewport corresponds to a mobile handset.
  static bool isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < AppSpacing.tabletBreakpoint;
  }

  /// Check whether the viewport corresponds to a tablet screen.
  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;
  }

  /// Resolve a value according to current screen breakpoint.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    required T tablet,
  }) {
    return isTablet(context) ? tablet : mobile;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppSpacing.tabletBreakpoint) {
          return tablet;
        }
        return mobile;
      },
    );
  }
}
