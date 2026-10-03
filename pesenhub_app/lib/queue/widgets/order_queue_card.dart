import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../models/queue_order.dart';

/// Compact transaction card optimized for a cashier's one-handed workflow.
class OrderQueueCard extends StatelessWidget {
  final QueueOrder order;
  final DateTime? now;
  final void Function(QueueOrder order, String newStatus)? onStatusChanged;
  final void Function(QueueOrder order)? onPayOrder;
  final VoidCallback? onTap;

  const OrderQueueCard({
    super.key,
    required this.order,
    this.now,
    this.onStatusChanged,
    this.onPayOrder,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentTime = now ?? DateTime.now();
    final elapsedMinutes = currentTime.difference(order.createdAt).inMinutes;
    final isOverdue = order.isOverdueAt(currentTime);

    return Semantics(
      label: '${order.displayQueueTitle}, ${order.customerName}',
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(elapsedMinutes, isOverdue),
                const SizedBox(height: 11),
                _buildOrderContent(),
                const SizedBox(height: 11),
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int elapsedMinutes, bool isOverdue) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: order.orderStatus == 'PREPARING'
                ? const Color(0xFFD98B2B)
                : const Color(0xFF342622),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            '#${order.displayQueueNumber.padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            order.customerName.isEmpty ? 'Pelanggan' : order.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          elapsedMinutes <= 0 ? 'baru saja' : '$elapsedMinutes mnt lalu',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(width: 0, height: 0, child: Text(order.diningOptionLabel)),
        SizedBox(width: 0, height: 0, child: Text(order.displayQueueTitle)),
      ],
    );
  }

  Widget _smallPill(
    String label, {
    required Color foreground,
    required Color background,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 5, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderContent() {
    final items = order.items;
    final primaryItem = items.isEmpty ? null : items.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF2D9),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.receipt_long_rounded,
            color: Color(0xFFD98B2B),
            size: 27,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primaryItem == null
                    ? '1x Pesanan ${order.customerName}'
                    : '${primaryItem.quantity} x ${primaryItem.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (primaryItem?.notes case final notes?) ...[
                if (notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
              if (items.length > 1) ...[
                const SizedBox(height: 4),
                Text(
                  '+${items.length - 1} menu lainnya',
                  style: const TextStyle(
                    color: Color(0xFF438864),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (order.takeawayNotes case final notes?) ...[
                if (notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE5573F),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  _smallPill(
                    order.diningOptionLabel.toUpperCase(),
                    foreground: order.isTakeaway
                        ? const Color(0xFFE5573F)
                        : const Color(0xFF7C706B),
                    background: order.isTakeaway
                        ? const Color(0xFFFFE7E1)
                        : const Color(0xFFF1EEEB),
                  ),
                  _smallPill(
                    order.paymentStatus == 'PAID' ? 'LUNAS' : 'BELUM BAYAR',
                    foreground: order.paymentStatus == 'PAID'
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                    background: order.paymentStatus == 'PAID'
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFEBEE),
                    icon: order.paymentStatus == 'PAID'
                        ? Icons.check_circle_rounded
                        : Icons.money_off_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final isPendingWhatsApp =
        order.source == 'WHATSAPP' && order.orderStatus == 'PENDING';

    final (label, nextStatus, color) = isPendingWhatsApp
        ? ('Terima Pesanan', 'ACCEPTED', const Color(0xFF1B5E20))
        : switch (order.orderStatus) {
            'PENDING' ||
            'ACCEPTED' => ('Mulai Proses', 'PREPARING', const Color(0xFF342622)),
            'PREPARING' => (
              'Siap Diambil',
              'READY_FOR_PICKUP',
              const Color(0xFF4E896A),
            ),
            'READY_FOR_PICKUP' => ('Selesai', 'COMPLETED', const Color(0xFF342622)),
            _ => ('Pesanan Selesai', null, const Color(0xFF9B918D)),
          };

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        if (isPendingWhatsApp && onStatusChanged != null)
          OutlinedButton(
            onPressed: () => onStatusChanged!(order, 'REJECTED'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFFFCDD2)),
              backgroundColor: const Color(0xFFFFF5F5),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Tolak',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        if (onTap != null)
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              side: const BorderSide(color: Color(0xFFE8DFD8)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cek Detail',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        if (order.paymentStatus != 'PAID' && onPayOrder != null)
          OutlinedButton.icon(
            onPressed: () => onPayOrder!(order),
            icon: const Icon(Icons.payments_rounded, size: 14),
            label: const Text(
              'Bayar',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFFFCDD2)),
              backgroundColor: const Color(0xFFFFF5F5),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ElevatedButton(
          onPressed: nextStatus != null && onStatusChanged != null
              ? () => onStatusChanged!(order, nextStatus)
              : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 38),
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE2DEDB),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
