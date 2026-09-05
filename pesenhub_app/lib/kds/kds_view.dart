import 'package:flutter/material.dart';
import '../../queue/models/queue_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_feedback.dart';
import 'controllers/kds_controller.dart';
import 'widgets/kds_ticket_card.dart';

/// KdsView provides an adaptive kitchen display monitor for tablets and mobile devices.
/// Fulfills Issue #30 Criteria #1, #2, #3, #4, and #5.
class KdsView extends StatefulWidget {
  final KdsController controller;
  final Future<QueueOrder> Function(
    String orderId,
    String targetStatus,
    int expectedVersion,
  )?
  transitionFn;

  const KdsView({super.key, required this.controller, this.transitionFn});

  @override
  State<KdsView> createState() => _KdsViewState();
}

class _KdsViewState extends State<KdsView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _executeQuickAction(QueueOrder order) async {
    final targetLabel = order.orderStatus == 'ACCEPTED'
        ? 'Sedang Dimasak'
        : 'Siap Diambil';
    final success = await widget.controller.executeQuickAction(
      order,
      transitionFn: widget.transitionFn,
    );
    if (!mounted) return;
    AppFeedback.show(
      context,
      message: success
          ? '${order.orderNumber} dipindahkan ke $targetLabel.'
          : '${order.orderNumber} gagal diperbarui. Periksa koneksi lalu coba lagi.',
      type: success ? AppBannerType.success : AppBannerType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    if (controller.isLoading) {
      return const Center(
        child: AppLoadingState(message: 'Memuat tiket dapur...'),
      );
    }

    final orders = controller.filteredOrders;
    final now = controller.now;

    return SingleChildScrollView(
      key: const PageStorageKey('kds_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Error Banner (if any)
          if (controller.errorMessage != null) ...[
            AppBanner(
              message: controller.errorMessage!,
              type: AppBannerType.error,
              onClose: () => controller.setError(null),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // 2. KDS Header & Filter Chips
          _buildFilterBar(controller),
          const SizedBox(height: AppSpacing.lg),

          // 3. Orders Content (Criteria #1 & #5)
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: AppEmptyState(
                icon: Icons.soup_kitchen_outlined,
                title: 'Dapur Bersih!',
                description:
                    'Tidak ada pesanan aktif yang perlu dimasak saat ini.',
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isTablet =
                    constraints.maxWidth >= AppSpacing.tabletBreakpoint;

                if (isTablet) {
                  return _buildTabletGrid(orders, constraints.maxWidth, now);
                } else {
                  return _buildMobileList(orders, now);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(KdsController controller) {
    final allCount = controller.countForStatus('ALL');
    final acceptedCount = controller.countForStatus('ACCEPTED');
    final preparingCount = controller.countForStatus('PREPARING');

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildFilterChip(
          'Semua ($allCount)',
          'ALL',
          controller.statusFilter == 'ALL',
        ),
        _buildFilterChip(
          'Perlu Dimasak ($acceptedCount)',
          'ACCEPTED',
          controller.statusFilter == 'ACCEPTED',
        ),
        _buildFilterChip(
          'Sedang Dimasak ($preparingCount)',
          'PREPARING',
          controller.statusFilter == 'PREPARING',
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, bool isSelected) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => widget.controller.setStatusFilter(value),
      selectedColor: AppColors.primaryContainer,
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        color: isSelected ? AppColors.primary : AppColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusSm,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
    );
  }

  Widget _buildMobileList(List<QueueOrder> orders, DateTime now) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: orders.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final order = orders[index];
        return KdsTicketCard(
          key: ValueKey('kds_ticket_${order.id}'),
          order: order,
          now: now,
          isProcessing: widget.controller.isOrderProcessing(order.id),
          onQuickAction: () => _executeQuickAction(order),
        );
      },
    );
  }

  Widget _buildTabletGrid(
    List<QueueOrder> orders,
    double maxWidth,
    DateTime now,
  ) {
    // 2 or 3 columns depending on width
    final int columnCount = maxWidth >= 960 ? 3 : 2;
    final List<List<QueueOrder>> columns = List.generate(
      columnCount,
      (_) => [],
    );

    for (int i = 0; i < orders.length; i++) {
      columns[i % columnCount].add(orders[i]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(columnCount, (colIndex) {
        final colOrders = columns[colIndex];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: colIndex == 0 ? 0 : AppSpacing.md / 2,
              right: colIndex == columnCount - 1 ? 0 : AppSpacing.md / 2,
            ),
            child: Column(
              children: colOrders
                  .map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: KdsTicketCard(
                        key: ValueKey('kds_ticket_${order.id}'),
                        order: order,
                        now: now,
                        isProcessing: widget.controller.isOrderProcessing(
                          order.id,
                        ),
                        onQuickAction: () => _executeQuickAction(order),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      }),
    );
  }
}
