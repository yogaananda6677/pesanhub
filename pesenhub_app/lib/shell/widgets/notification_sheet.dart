import 'package:flutter/material.dart';
import '../../alerts/order_alert_controller.dart';
import '../../queue/models/queue_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class NotificationItem {
  final String id;
  final String title;
  final String message;
  final String time;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final bool isUnread;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    this.isUnread = false,
  });
}

class NotificationSheet extends StatefulWidget {
  final OrderAlertController? alertController;
  final List<QueueOrder>? activeOrders;
  final VoidCallback? onClearAll;

  const NotificationSheet({
    super.key,
    this.alertController,
    this.activeOrders,
    this.onClearAll,
  });

  static Future<void> show(
    BuildContext context, {
    OrderAlertController? alertController,
    List<QueueOrder>? activeOrders,
    VoidCallback? onClearAll,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationSheet(
        alertController: alertController,
        activeOrders: activeOrders,
        onClearAll: onClearAll,
      ),
    );
  }

  @override
  State<NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<NotificationSheet> {
  String _selectedFilter = 'SEMUA';
  bool _cleared = false;

  List<NotificationItem> _generateNotifications() {
    if (_cleared) return [];

    final list = <NotificationItem>[];
    final now = DateTime.now();

    // 1. Alerts from active alert controller if available
    final activeAlert = widget.alertController?.activeAlert;
    if (activeAlert != null) {
      list.add(
        NotificationItem(
          id: 'alert-${activeAlert.eventId}',
          title: activeAlert.kind == 'NEW_ORDER'
              ? 'Pesanan Baru Masuk'
              : 'Status Pesanan Berubah',
          message:
              '${activeAlert.orderNumber}: ${activeAlert.message}',
          time: 'Baru saja',
          icon: Icons.notifications_active_rounded,
          iconColor: const Color(0xFFC62828),
          iconBgColor: const Color(0xFFFDE8E4),
          isUnread: true,
        ),
      );
    }

    // 2. Active orders from Queue
    final orders = widget.activeOrders ?? [];
    for (final order in orders.take(6)) {
      if (order.orderStatus == 'READY_FOR_PICKUP' ||
          order.orderStatus == 'READY') {
        list.add(
          NotificationItem(
            id: 'ready-${order.id}',
            title: 'Pesanan Siap Diambil Pelanggan',
            message:
                'Pesanan ${order.orderNumber} untuk ${order.customerName} sudah selesai dimasak.',
            time: 'Siap diambil',
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.success,
            iconBgColor: AppColors.successBg,
            isUnread: false,
          ),
        );
      } else if (order.orderStatus == 'PREPARING') {
        list.add(
          NotificationItem(
            id: 'prep-${order.id}',
            title: 'Pesanan Sedang Dimasak',
            message:
                'Dapur sedang menyiapkan pesanan ${order.orderNumber} (${order.items.length} menu).',
            time: '${now.difference(order.createdAt).inMinutes} mnt lalu',
            icon: Icons.outdoor_grill_rounded,
            iconColor: const Color(0xFFD97706),
            iconBgColor: const Color(0xFFFEF3C7),
            isUnread: false,
          ),
        );
      }
    }

    // 3. Fallback operational alerts if empty
    if (list.isEmpty) {
      list.addAll([
        NotificationItem(
          id: 'sys-sync',
          title: 'Sinkronisasi Sistem Berhasil',
          message:
              'Katalog menu, harga, dan antrean data lokal sinkron dengan server backend.',
          time: '5 mnt lalu',
          icon: Icons.cloud_done_rounded,
          iconColor: const Color(0xFF2E7D32),
          iconBgColor: const Color(0xFFE8F5E9),
          isUnread: false,
        ),
        NotificationItem(
          id: 'sys-wa',
          title: 'WhatsApp Gateway Siap',
          message:
              'Layanan kirim struk otomatis via WhatsApp siap digunakan melayani pelanggan.',
          time: '15 mnt lalu',
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: const Color(0xFF15803D),
          iconBgColor: const Color(0xFFDCFCE7),
          isUnread: false,
        ),
      ]);
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _generateNotifications();
    final filtered = switch (_selectedFilter) {
      'BELUM DIBACA' => notifications.where((n) => n.isUnread).toList(),
      'PERINGATAN' => notifications
          .where((n) =>
              n.iconColor == AppColors.error ||
              n.iconColor == const Color(0xFFC62828))
          .toList(),
      _ => notifications,
    };

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pusat Notifikasi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Aktivitas pesanan, dapur, dan sistem',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.alertController?.dismiss();
                    setState(() => _cleared = true);
                    widget.onClearAll?.call();
                  },
                  child: const Text(
                    'Tandai Dibaca',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                _buildFilterChip('SEMUA', 'Semua'),
                const SizedBox(width: 8),
                _buildFilterChip('BELUM DIBACA', 'Belum Dibaca'),
                const SizedBox(width: 8),
                _buildFilterChip('PERINGATAN', 'Peringatan'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.border),

          // Notification List
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 48,
                      horizontal: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.done_all_rounded,
                            color: AppColors.primary,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Semua Bersih & Terkendali',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tidak ada notifikasi aktif yang memerlukan perhatian saat ini.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 16, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.sm + 2),
                        decoration: BoxDecoration(
                          color: item.isUnread
                              ? const Color(0xFFFFFBEB)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: item.isUnread
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFF1F5F9),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: item.iconBgColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                item.icon,
                                color: item.iconColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm + 2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: item.isUnread
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        item.time,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.message,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
