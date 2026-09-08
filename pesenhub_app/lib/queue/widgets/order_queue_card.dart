import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/queue_order.dart';

/// OrderQueueCard renders an order queue card matching the streamlined kitchen queue design.
/// Fulfills Issue #147: Redesign Antrean Dapur.
class OrderQueueCard extends StatelessWidget {
  final QueueOrder order;
  final DateTime? now;
  final void Function(QueueOrder order, String newStatus)? onStatusChanged;
  final VoidCallback? onTap;

  const OrderQueueCard({
    super.key,
    required this.order,
    this.now,
    this.onStatusChanged,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOverdue = now != null
        ? order.isOverdueAt(now!)
        : order.isOverdue;

    return Semantics(
      label: '${order.displayQueueTitle} ${order.orderNumber}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Teal Card Header
              _buildHeader(context, isOverdue),

              // 2. Card Body
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isOverdue) ...[
                      _buildOverdueBanner(),
                      const SizedBox(height: 12),
                    ],

                    // Gray Item Container
                    _buildItemsBox(),

                    const SizedBox(height: 16),

                    // Action Button
                    _buildActionButton(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isOverdue) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final isLargeText = textScale > 1.3;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            order.isTakeaway
                ? Icons.shopping_bag_outlined
                : Icons.restaurant_outlined,
            size: 14,
            color: const Color(0xFF1B7C71),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              order.diningOptionLabel,
              style: const TextStyle(
                color: Color(0xFF1B7C71),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (isLargeText) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(color: Color(0xFF1B7C71)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Color(0xFF1B7C71),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    order.displayQueueTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.formattedDateTime,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            badge,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1B7C71), // Teal
      ),
      child: Row(
        children: [
          // White rounded square with receipt icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFF1B7C71),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // Title & Datetime
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  order.displayQueueTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  order.formattedDateTime,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Dining Option Pill Badge
          badge,
        ],
      ),
    );
  }

  Widget _buildOverdueBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.timer_off_rounded, size: 16, color: AppColors.error),
          SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'TERLAMBAT (> 15 MENIT BELUM SELESAI)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.error,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsBox() {
    final items = order.items;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: items.isEmpty
          ? Text(
              '1 x ${order.customerName.isNotEmpty ? order.customerName : "Pesanan"}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Text(
                    '${items[i].quantity} x ${items[i].name}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  if (items[i].notes != null && items[i].notes!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      items[i].notes!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4B5563),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    final String label;
    final IconData icon;
    final String? nextStatus;

    switch (order.orderStatus) {
      case 'PENDING':
      case 'ACCEPTED':
        label = 'Mulai Proses';
        icon = Icons.soup_kitchen_outlined;
        nextStatus = 'PREPARING';
        break;
      case 'PREPARING':
        label = 'Siap Diambil';
        icon = Icons.check_circle_outline_rounded;
        nextStatus = 'READY_FOR_PICKUP';
        break;
      case 'READY_FOR_PICKUP':
        label = 'Selesai';
        icon = Icons.done_all_rounded;
        nextStatus = 'COMPLETED';
        break;
      case 'COMPLETED':
        label = 'Pesanan Selesai';
        icon = Icons.task_alt_rounded;
        nextStatus = null;
        break;
      default:
        label = 'Perbarui Status';
        icon = Icons.update_rounded;
        nextStatus = null;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4FA89B),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        onPressed: nextStatus != null && onStatusChanged != null
            ? () => onStatusChanged!(order, nextStatus!)
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
