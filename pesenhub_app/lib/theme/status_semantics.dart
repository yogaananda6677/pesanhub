import 'package:flutter/material.dart';
import 'app_colors.dart';

/// StatusSemantics binds status codes to human-readable Indonesian labels,
/// distinct icons, and accessible color pairings.
/// Fulfills Acceptance Criteria #2: Never relies on color alone.
@immutable
class StatusSemantics {
  final String code;
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  const StatusSemantics({
    required this.code,
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  /// Status mapping for Order Lifecycle state machine.
  static StatusSemantics forOrder(String rawStatus) {
    final status = rawStatus.toUpperCase().trim();
    switch (status) {
      case 'PENDING':
        return const StatusSemantics(
          code: 'PENDING',
          label: 'Menunggu Konfirmasi',
          icon: Icons.hourglass_top_rounded,
          foregroundColor: AppColors.statusPending,
          backgroundColor: AppColors.statusPendingBg,
        );
      case 'ACCEPTED':
        return const StatusSemantics(
          code: 'ACCEPTED',
          label: 'Diterima Kasir',
          icon: Icons.check_circle_outline_rounded,
          foregroundColor: AppColors.statusAccepted,
          backgroundColor: AppColors.statusAcceptedBg,
        );
      case 'PREPARING':
        return const StatusSemantics(
          code: 'PREPARING',
          label: 'Sedang Dimasak',
          icon: Icons.outdoor_grill_outlined,
          foregroundColor: AppColors.statusPreparing,
          backgroundColor: AppColors.statusPreparingBg,
        );
      case 'READY_FOR_PICKUP':
        return const StatusSemantics(
          code: 'READY_FOR_PICKUP',
          label: 'Siap Diambil',
          icon: Icons.shopping_bag_outlined,
          foregroundColor: AppColors.statusReady,
          backgroundColor: AppColors.statusReadyBg,
        );
      case 'COMPLETED':
        return const StatusSemantics(
          code: 'COMPLETED',
          label: 'Pesanan Selesai',
          icon: Icons.task_alt_rounded,
          foregroundColor: AppColors.statusCompleted,
          backgroundColor: AppColors.statusCompletedBg,
        );
      case 'REJECTED':
        return const StatusSemantics(
          code: 'REJECTED',
          label: 'Pesanan Ditolak',
          icon: Icons.cancel_outlined,
          foregroundColor: AppColors.statusRejected,
          backgroundColor: AppColors.statusRejectedBg,
        );
      case 'CANCELLED':
        return const StatusSemantics(
          code: 'CANCELLED',
          label: 'Pesanan Dibatalkan',
          icon: Icons.block_outlined,
          foregroundColor: AppColors.statusCancelled,
          backgroundColor: AppColors.statusCancelledBg,
        );
      default:
        return StatusSemantics(
          code: status,
          label: status,
          icon: Icons.info_outline_rounded,
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceVariant,
        );
    }
  }

  /// Status mapping for Midtrans/Cash Payment States.
  static StatusSemantics forPayment(String rawStatus) {
    final status = rawStatus.toUpperCase().trim();
    switch (status) {
      case 'UNPAID':
        return const StatusSemantics(
          code: 'UNPAID',
          label: 'Belum Bayar',
          icon: Icons.money_off_outlined,
          foregroundColor: AppColors.paymentUnpaid,
          backgroundColor: AppColors.paymentUnpaidBg,
        );
      case 'PAID':
        return const StatusSemantics(
          code: 'PAID',
          label: 'Sudah Lunas',
          icon: Icons.paid_outlined,
          foregroundColor: AppColors.paymentPaid,
          backgroundColor: AppColors.paymentPaidBg,
        );
      case 'FAILED':
        return const StatusSemantics(
          code: 'FAILED',
          label: 'Pembayaran Gagal',
          icon: Icons.error_outline_rounded,
          foregroundColor: AppColors.paymentFailed,
          backgroundColor: AppColors.paymentFailedBg,
        );
      case 'EXPIRED':
        return const StatusSemantics(
          code: 'EXPIRED',
          label: 'Kedaluwarsa',
          icon: Icons.timer_off_outlined,
          foregroundColor: AppColors.paymentExpired,
          backgroundColor: AppColors.paymentExpiredBg,
        );
      case 'REFUNDED':
        return const StatusSemantics(
          code: 'REFUNDED',
          label: 'Dikembalikan',
          icon: Icons.replay_rounded,
          foregroundColor: AppColors.paymentRefunded,
          backgroundColor: AppColors.paymentRefundedBg,
        );
      default:
        return StatusSemantics(
          code: status,
          label: status,
          icon: Icons.help_outline_rounded,
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceVariant,
        );
    }
  }

  /// Status mapping for Order Creation Sources.
  static StatusSemantics forSource(String rawSource) {
    final source = rawSource.toUpperCase().trim();
    switch (source) {
      case 'CASHIER_MANUAL':
        return const StatusSemantics(
          code: 'CASHIER_MANUAL',
          label: 'Kasir Manual',
          icon: Icons.point_of_sale_rounded,
          foregroundColor: AppColors.sourceCashier,
          backgroundColor: AppColors.sourceCashierBg,
        );
      case 'CUSTOMER_WEB':
        return const StatusSemantics(
          code: 'CUSTOMER_WEB',
          label: 'Web Customer',
          icon: Icons.language_rounded,
          foregroundColor: AppColors.sourceWeb,
          backgroundColor: AppColors.sourceWebBg,
        );
      case 'WHATSAPP':
        return const StatusSemantics(
          code: 'WHATSAPP',
          label: 'WhatsApp',
          icon: Icons.chat_bubble_outline_rounded,
          foregroundColor: AppColors.sourceWhatsApp,
          backgroundColor: AppColors.sourceWhatsAppBg,
        );
      default:
        return StatusSemantics(
          code: source,
          label: source,
          icon: Icons.receipt_long_outlined,
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceVariant,
        );
    }
  }
}
