import 'package:flutter/material.dart';

/// AppColors defines the centralized color palette for PesenHub.
/// Built for high visual contrast and fast scanning in kitchen and cashier environments.
abstract final class AppColors {
  // Brand Primary & Accent (Cocoa Brown & Butter Gold - Martabak & Terang Bulan)
  static const Color primary = Color(0xFF7A321F);
  static const Color primaryHover = Color(0xFF4B2118);
  static const Color primaryContainer = Color(0xFFFEF3ED);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color secondary = Color(0xFFF2A72B);
  static const Color secondaryContainer = Color(0xFFFFF1D2);
  static const Color onSecondary = Color(0xFFFFFFFF);

  // Terracotta Warm Palette Tokens
  static const Color terracottaDark = Color(0xFF2D231E);
  static const Color terracotta = Color(0xFF8D321F);
  static const Color terracottaLight = Color(0xFFF9EFE7);
  static const Color terracottaSoft = Color(0xFFF9EFE7);
  static const Color terracottaBorder = Color(0xFFF0DCD3);
  static const Color terracottaGradientStart = Color(0xFF8D321F);
  static const Color terracottaGradientEnd = Color(0xFFB8482A);

  // Surfaces & Backgrounds
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color outlineVariant = Color(0xFFE2E8F0);
  static const Color borderFocus = Color(0xFF7A321F);
  static const Color creamBg = Color(0xFFFBF8F5);
  static const Color warmSurface = Color(0xFFF7F5F2);
  static const Color surfaceWarm = Color(0xFFF7F5F2);
  static const Color cardBorder = Color(0xFFF0EBE6);
  static const Color cardBorderSubtle = Color(0xFFF4EEEA);
  static const Color cardBorderAlt = Color(0xFFF3ECE6);

  // Typography & Slate Colors
  static const Color textPrimary = Color(0xFF2B1B16);
  static const Color textSecondary = Color(0xFF75645D);
  static const Color textMuted = Color(0xFF8E9A93);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color slate = Color(0xFF64748B);
  static const Color slateLight = Color(0xFF94A3B8);
  static const Color slateDark = Color(0xFF475569);
  static const Color neutralText = Color(0xFF7A6B63);
  static const Color neutralTextLight = Color(0xFF9E8E85);
  static const Color neutralTextMuted = Color(0xFF8C7E77);

  // Distinct Accent Semantics
  static const Color accentBlue = Color(0xFF0284C7);
  static const Color accentBlueBg = Color(0xFFE0F2FE);
  static const Color accentGreen = Color(0xFF16A34A);
  static const Color accentGreenDeep = Color(0xFF2E7D32);
  static const Color accentGreenBg = Color(0xFFE8F5E9);
  static const Color accentGreenBorder = Color(0xFFC8E6C9);
  static const Color accentRed = Color(0xFFC62828);
  static const Color accentRedBg = Color(0xFFFFEBEE);
  static const Color accentRedBorder = Color(0xFFFFCDD2);
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentAmberBg = Color(0xFFFEF3C7);
  // Semantic Feedback Colors
  static const Color success = Color(0xFF15803D);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFB45309);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFB91C1C);
  static const Color errorBg = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF1D4ED8);
  static const Color infoBg = Color(0xFFDBEAFE);

  // Order Status Colors
  static const Color statusPending = Color(0xFFB45309);
  static const Color statusPendingBg = Color(0xFFFEF3C7);

  static const Color statusAccepted = Color(0xFF1D4ED8);
  static const Color statusAcceptedBg = Color(0xFFDBEAFE);

  static const Color statusPreparing = Color(0xFF4338CA);
  static const Color statusPreparingBg = Color(0xFFE0E7FF);

  static const Color statusReady = Color(0xFF15803D);
  static const Color statusReadyBg = Color(0xFFDCFCE7);

  static const Color statusCompleted = Color(0xFF475569);
  static const Color statusCompletedBg = Color(0xFFF1F5F9);

  static const Color statusRejected = Color(0xFF9F1239);
  static const Color statusRejectedBg = Color(0xFFFFE4E6);

  static const Color statusCancelled = Color(0xFF6B7280);
  static const Color statusCancelledBg = Color(0xFFF3F4F6);

  // Payment Status Colors
  static const Color paymentUnpaid = Color(0xFFB45309);
  static const Color paymentUnpaidBg = Color(0xFFFEF3C7);

  static const Color paymentPaid = Color(0xFF15803D);
  static const Color paymentPaidBg = Color(0xFFDCFCE7);

  static const Color paymentFailed = Color(0xFFB91C1C);
  static const Color paymentFailedBg = Color(0xFFFEE2E2);

  static const Color paymentExpired = Color(0xFF6B7280);
  static const Color paymentExpiredBg = Color(0xFFF3F4F6);

  static const Color paymentRefunded = Color(0xFF0E7490);
  static const Color paymentRefundedBg = Color(0xFFCFFAFE);

  // Order Source Colors
  static const Color sourceCashier = Color(0xFFC2410C);
  static const Color sourceCashierBg = Color(0xFFFFEDD5);

  static const Color sourceWeb = Color(0xFF6D28D9);
  static const Color sourceWebBg = Color(0xFFEDE9FE);

  static const Color sourceWhatsApp = Color(0xFF047857);
  static const Color sourceWhatsAppBg = Color(0xFFD1FAE5);

  static const Color sourceGrabFood = Color(0xFF00B14F);
  static const Color sourceGrabFoodBg = Color(0xFFE8F8EE);

  static const Color sourceGoFood = Color(0xFFEE2737);
  static const Color sourceGoFoodBg = Color(0xFFFEECEE);

  static const Color sourceShopeeFood = Color(0xFFEE4D2D);
  static const Color sourceShopeeFoodBg = Color(0xFFFEF0ED);
}
