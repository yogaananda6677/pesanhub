import 'package:flutter/material.dart';
import '../../queue/models/queue_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_status_badge.dart';

/// OrderPaymentCard displays the independent payment state of an order.
/// Fulfills Issue #29 Criteria #3 (Payment status is separate from order status).
class OrderPaymentCard extends StatelessWidget {
  final QueueOrder order;
  final VoidCallback? onAcceptPayment;

  const OrderPaymentCard({
    super.key,
    required this.order,
    this.onAcceptPayment,
  });

  @override
  Widget build(BuildContext context) {
    final isUnpaid = order.paymentStatus != 'PAID';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Status Pembayaran',
                  style: AppTypography.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppStatusBadge.payment(order.paymentStatus),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Total Transaksi:',
                  style: AppTypography.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Rp ${order.totalAmount}',
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (isUnpaid && onAcceptPayment != null) ...[
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: onAcceptPayment,
              icon: const Icon(Icons.payments_rounded, size: 16),
              label: const Text('Terima Pembayaran'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            isUnpaid
                ? 'Perhatian: Pesanan wajib dibayar lunas sebelum diselesaikan.'
                : 'Catatan: Status pembayaran tercatat secara independen dan tidak menggantikan tahapan dapur.',
            style: AppTypography.bodySmall.copyWith(
              color: isUnpaid ? AppColors.error : AppColors.textSecondary,
              fontStyle: isUnpaid ? FontStyle.normal : FontStyle.italic,
              fontWeight: isUnpaid ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
