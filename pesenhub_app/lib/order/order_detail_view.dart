import 'package:flutter/material.dart';
import '../queue/models/queue_order.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_status_badge.dart';
import 'controllers/order_detail_controller.dart';
import 'widgets/conflict_resolution_dialog.dart';
import 'widgets/order_payment_card.dart';
import 'widgets/order_status_timeline.dart';

/// OrderDetailView displays complete operational details of an order,
/// a visual order lifecycle timeline separated from payment status,
/// and exactly one contextual primary quick action per role and status.
/// Fulfills Issue #29 Criteria #1, #2, #3, #4, and #5.
class OrderDetailView extends StatelessWidget {
  final OrderDetailController controller;
  final Future<QueueOrder> Function(
    String orderId,
    String targetStatus,
    int expectedVersion,
  )?
  transitionFn;
  final Future<QueueOrder> Function(String orderId)? reloadFn;

  const OrderDetailView({
    super.key,
    required this.controller,
    this.transitionFn,
    this.reloadFn,
  });

  static Future<void> show({
    required BuildContext context,
    required QueueOrder order,
    String role = 'STAFF',
    Future<QueueOrder> Function(
      String orderId,
      String targetStatus,
      int expectedVersion,
    )?
    transitionFn,
    Future<QueueOrder> Function(String orderId)? reloadFn,
  }) {
    final controller = OrderDetailController(initialOrder: order, role: role);
    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    if (isTablet) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 820),
            child: OrderDetailView(
              controller: controller,
              transitionFn: transitionFn,
              reloadFn: reloadFn,
            ),
          ),
        ),
      );
    } else {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
            ),
            child: OrderDetailView(
              controller: controller,
              transitionFn: transitionFn,
              reloadFn: reloadFn,
            ),
          ),
        ),
      );
    }
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    return '${diff.inHours}j lalu';
  }

  String _maskPhone(String phone) {
    if (phone.length <= 6) return phone;
    return '${phone.substring(0, 4)}****${phone.substring(phone.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final order = controller.order;
        final primaryAction = controller.primaryAction;
        final secondaryAction = controller.secondaryAction;
        final isExecuting = controller.isExecutingAction;
        final conflictMsg = controller.conflictMessage;
        final errorMsg = controller.errorMessage;
        final successMsg = controller.successMessage;

        final drinks = order.items.where((i) => i.isDrink).toList();
        final foodItems = order.items.where((i) => !i.isDrink).toList();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                order.orderNumber,
                                style: AppTypography.headline,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: AppSpacing.borderRadiusSm,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                'v${order.version}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppStatusBadge.source(order.source),
                            Text(
                              '• ${_formatRelativeTime(order.createdAt)}',
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 2. Scrollable Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Criteria #2 & #3: Conflict Warning Banner & Resolution
                    if (conflictMsg != null) ...[
                      AppBanner(
                        message: conflictMsg,
                        type: controller.activeConflict?.isSafe == true
                            ? AppBannerType.warning
                            : AppBannerType.error,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.sm,
                        children: [
                          if (controller.activeConflict != null &&
                              controller.activeConflict!.isSafe)
                            TextButton.icon(
                              icon: const Icon(Icons.tune_rounded, size: 16),
                              label: const Text('Pilih Resolusi Konflik'),
                              onPressed: () {
                                ConflictResolutionDialog.show(
                                  context: context,
                                  classification: controller.activeConflict!,
                                  onResolve: (strategy) {
                                    controller.resolveConflict(
                                      strategy: strategy,
                                    );
                                  },
                                );
                              },
                            ),
                          TextButton.icon(
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Muat Ulang Data Terbaru'),
                            onPressed: () async {
                              if (reloadFn != null) {
                                final fresh = await reloadFn!(order.id);
                                controller.updateOrder(fresh);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Error Banner
                    if (errorMsg != null) ...[
                      AppBanner(message: errorMsg, type: AppBannerType.error),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Success Banner
                    if (successMsg != null) ...[
                      AppBanner(
                        message: successMsg,
                        type: AppBannerType.success,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Customer & Service Info Card
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Pelanggan:',
                                style: AppTypography.labelSmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  order.customerName,
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (order.customerPhone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Nomor Kontak:',
                                  style: AppTypography.labelSmall,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _maskPhone(order.customerPhone),
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          const Divider(),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Layanan:',
                                style: AppTypography.labelSmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: order.isTakeaway
                                        ? AppColors.warningBg
                                        : AppColors.surfaceVariant,
                                    borderRadius: AppSpacing.borderRadiusSm,
                                    border: Border.all(
                                      color: order.isTakeaway
                                          ? AppColors.warning
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    order.isTakeaway
                                        ? 'Bungkus / Takeaway'
                                        : 'Makan di Tempat',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: order.isTakeaway
                                          ? AppColors.warning
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (order.isTakeaway &&
                              order.takeawayNotes != null &&
                              order.takeawayNotes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: AppColors.warningBg.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: AppSpacing.borderRadiusSm,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.takeout_dining_rounded,
                                    size: 16,
                                    color: AppColors.warning,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      'Catatan Kemasan: ${order.takeawayNotes}',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Criteria #3: Separate Order Lifecycle Timeline
                    OrderStatusTimeline(orderStatus: order.orderStatus),
                    const SizedBox(height: AppSpacing.md),

                    // Criteria #3: Separate Payment Status Card
                    OrderPaymentCard(order: order),
                    const SizedBox(height: AppSpacing.md),

                    // Highlighted Barista Drinks Section
                    if (drinks.isNotEmpty) ...[
                      AppCard(
                        backgroundColor: AppColors.infoBg.withValues(
                          alpha: 0.3,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_cafe_rounded,
                                  size: 18,
                                  color: AppColors.info,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    'Minuman Barista (${drinks.length})',
                                    style: AppTypography.titleMedium.copyWith(
                                      color: AppColors.info,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            ...drinks.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.quantity}x ${item.name}',
                                        style: AppTypography.bodyLarge.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      'Rp ${item.subtotal}',
                                      style: AppTypography.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Kitchen Food Items Section
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Menu Makanan / Dapur:',
                            style: AppTypography.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ...foodItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item.quantity}x ${item.name}',
                                          style: AppTypography.bodyLarge
                                              .copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (item.notes != null &&
                                            item.notes!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            item.notes!,
                                            style: AppTypography.bodySmall
                                                .copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    'Rp ${item.subtotal}',
                                    style: AppTypography.titleMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // 3. Footer: Contextual Quick Action (Criteria #1 & #4)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Criteria #1: Exactly ONE Primary Action Button based on state
                  if (primaryAction != null) ...[
                    AppButton(
                      label: isExecuting ? 'Menyimpan...' : primaryAction.label,
                      icon: isExecuting ? null : primaryAction.icon,
                      isFullWidth: true,
                      onPressed: isExecuting
                          ? null
                          : () => controller.executeAction(
                              primaryAction,
                              transitionFn: transitionFn,
                              reloadFn: reloadFn,
                            ),
                    ),
                    if (primaryAction.helperText != null) ...[
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          primaryAction.helperText!,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ] else if (controller.role == 'CUSTOMER') ...[
                    // Criteria #4: Unauthorized role message
                    const Center(
                      child: Text(
                        'Mode Pelanggan: Hanya dapat melihat status pesanan.',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ] else if (controller.role == 'KDS') ...[
                    const Center(
                      child: Text(
                        'Mode Dapur (KDS): Aksi aktif hanya saat pesanan berstatus Memasak.',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ] else ...[
                    Center(
                      child: Text(
                        'Pesanan telah mencapai status akhir (${order.orderStatus}).',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ],

                  // Secondary Action (e.g. Reject / Cancel)
                  if (secondaryAction != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      icon: Icon(secondaryAction.icon, size: 18),
                      label: Text(secondaryAction.label),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      onPressed: isExecuting
                          ? null
                          : () => controller.executeAction(
                              secondaryAction,
                              transitionFn: transitionFn,
                              reloadFn: reloadFn,
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
