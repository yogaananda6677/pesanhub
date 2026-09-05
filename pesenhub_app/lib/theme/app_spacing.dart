import 'package:flutter/material.dart';

/// AppSpacing defines standard spacing, radius, and elevation tokens.
abstract final class AppSpacing {
  // 4-point Spacing Grid
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  // Corner Radii
  static const double radiusSm = 10.0;
  static const double radiusMd = 14.0;
  static const double radiusLg = 18.0;
  static const double radiusFull = 999.0;

  static const BorderRadius borderRadiusSm = BorderRadius.all(
    Radius.circular(radiusSm),
  );
  static const BorderRadius borderRadiusMd = BorderRadius.all(
    Radius.circular(radiusMd),
  );
  static const BorderRadius borderRadiusLg = BorderRadius.all(
    Radius.circular(radiusLg),
  );
  static const BorderRadius borderRadiusFull = BorderRadius.all(
    Radius.circular(radiusFull),
  );

  // Accessibility Touch Target
  static const double minTouchTarget = 48.0;

  // Responsive Layout Breakpoints
  static const double tabletBreakpoint = 600.0;
}
