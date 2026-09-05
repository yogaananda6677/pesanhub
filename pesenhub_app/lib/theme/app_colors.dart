import 'package:flutter/material.dart';

/// AppColors defines the centralized color palette for PesenHub.
/// Built for high visual contrast and fast scanning in kitchen and cashier environments.
abstract final class AppColors {
  // Brand Primary & Accent
  static const Color primary = Color(0xFF176B4D);
  static const Color primaryHover = Color(0xFF104C38);
  static const Color primaryContainer = Color(0xFFEAF6F0);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color secondary = Color(0xFFE98A15);
  static const Color secondaryContainer = Color(0xFFFFF5E7);
  static const Color onSecondary = Color(0xFFFFFFFF);

  // Surfaces & Backgrounds
  static const Color background = Color(0xFFF7F6F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFFBFCFB);
  static const Color border = Color(0xFFDCE4DF);
  static const Color borderFocus = Color(0xFF176B4D);

  // Typography Colors
  static const Color textPrimary = Color(0xFF18251F);
  static const Color textSecondary = Color(0xFF6C7972);
  static const Color textMuted = Color(0xFF8E9A93);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

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
}
