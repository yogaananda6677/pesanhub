import 'package:flutter/material.dart';
import '../alerts/order_alert_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class OrderHeadsUpAlert extends StatelessWidget {
  final OrderAlert alert;
  final VoidCallback onDismiss;
  const OrderHeadsUpAlert({
    super.key,
    required this.alert,
    required this.onDismiss,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Semantics(
      container: true,
      liveRegion: true,
      label: 'Alert pesanan ${alert.orderNumber}: ${alert.message}',
      child: Material(
        elevation: 8,
        borderRadius: AppSpacing.borderRadiusSm,
        color: AppColors.warningBg,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListTile(
            key: const Key('order-heads-up-alert'),
            leading: const Icon(
              Icons.notifications_active_rounded,
              color: AppColors.warning,
            ),
            title: Text(
              alert.orderNumber,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(alert.message),
            trailing: IconButton(
              tooltip: 'Tutup alert',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
      ),
    ),
  );
}
