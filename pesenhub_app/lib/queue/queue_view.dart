import 'package:flutter/material.dart';
import '../order/order_detail_view.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_feedback.dart';
import 'controllers/queue_controller.dart';
import 'models/queue_order.dart';
import 'models/queue_state.dart';
import 'widgets/order_queue_card.dart';
import 'widgets/queue_filter_bar.dart';

/// QueueView renders the unified order queue with source badges, visual alerts, and filters.
/// Fulfills Issue #26 Acceptance Criteria #1, #2, #3, #4, and #5.
class QueueView extends StatefulWidget {
  final QueueController controller;
  final VoidCallback? onRefresh;
  final void Function(QueueOrder order, String newStatus)? onStatusChanged;

  const QueueView({
    super.key,
    required this.controller,
    this.onRefresh,
    this.onStatusChanged,
  });

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant QueueView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
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

  void _handleStatusChanged(QueueOrder order, String newStatus) {
    var updated = true;
    if (widget.onStatusChanged != null) {
      widget.onStatusChanged!(order, newStatus);
    } else {
      updated = widget.controller.updateOrderStatus(order.id, newStatus);
    }
    AppFeedback.show(
      context,
      message: updated
          ? '${order.orderNumber} dipindahkan ke ${_statusLabel(newStatus)}.'
          : '${order.orderNumber} tidak dapat diperbarui. Muat ulang lalu coba lagi.',
      type: updated ? AppBannerType.success : AppBannerType.error,
    );
  }

  String _statusLabel(String status) => switch (status) {
    'ACCEPTED' => 'Diterima',
    'PREPARING' => 'Sedang Dimasak',
    'READY_FOR_PICKUP' => 'Siap Diambil',
    'COMPLETED' => 'Selesai',
    _ => status,
  };

  void _openOrderDetail(QueueOrder order) {
    OrderDetailView.show(
      context: context,
      order: order,
      role: 'STAFF',
      transitionFn: (orderId, targetStatus, expectedVersion) async {
        _handleStatusChanged(order, targetStatus);
        return widget.controller.allOrders.firstWhere((o) => o.id == orderId);
      },
      reloadFn: (orderId) async {
        return widget.controller.allOrders.firstWhere((o) => o.id == orderId);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    switch (state.status) {
      case QueueStatus.loading:
        return const Center(
          child: AppLoadingState(message: 'Memuat antrean pesanan...'),
        );

      case QueueStatus.error:
        return Center(
          child: AppErrorState(
            message: state.errorMessage ?? 'Gagal memuat antrean pesanan.',
            onRetry: widget.onRefresh,
          ),
        );

      case QueueStatus.empty:
      case QueueStatus.success:
        return _buildContent(context, state);
    }
  }

  Widget _buildContent(BuildContext context, QueueState state) {
    final orders = widget.controller.filteredOrders;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet =
            constraints.maxWidth >= AppSpacing.tabletBreakpoint;

        return SingleChildScrollView(
          key: const PageStorageKey('unified_queue_scroll'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Offline or Stale Alert Banner
              if (state.isOffline) ...[
                const AppBanner(
                  message:
                      'Mode Offline: Menampilkan data antrean lokal. Sinkronisasi tertunda.',
                  type: AppBannerType.warning,
                ),
                const SizedBox(height: AppSpacing.md),
              ] else if (state.isStale) ...[
                const AppBanner(
                  message:
                      'Data Usang: Hubungan real-time terputus. Menampilkan snapshot terakhir.',
                  type: AppBannerType.warning,
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 2. Filter Bar
              QueueFilterBar(
                selectedStatus: widget.controller.statusFilter,
                selectedSource: widget.controller.sourceFilter,
                onStatusChanged: widget.controller.setStatusFilter,
                onSourceChanged: widget.controller.setSourceFilter,
                onSearchChanged: widget.controller.setSearchQuery,
                countForStatus: widget.controller.countForStatus,
              ),
              const SizedBox(height: AppSpacing.lg),

              // 3. Orders List or Empty State
              if (orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: AppEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Tidak Ada Pesanan',
                    description:
                        'Tidak ada pesanan yang sesuai dengan filter saat ini.',
                  ),
                )
              else if (isTablet)
                _buildTabletOrderGrid(orders)
              else
                _buildMobileOrderList(orders),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileOrderList(List<QueueOrder> orders) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: orders.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final order = orders[index];
        return OrderQueueCard(
          key: ValueKey('order_card_${order.id}'),
          order: order,
          now: widget.controller.now,
          onStatusChanged: _handleStatusChanged,
          onTap: () => _openOrderDetail(order),
        );
      },
    );
  }

  Widget _buildTabletOrderGrid(List<QueueOrder> orders) {
    final halfLength = (orders.length / 2).ceil();
    final col1 = orders.sublist(0, halfLength);
    final col2 = orders.sublist(halfLength);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: col1.map((order) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: OrderQueueCard(
                  key: ValueKey('order_card_${order.id}'),
                  order: order,
                  now: widget.controller.now,
                  onStatusChanged: _handleStatusChanged,
                  onTap: () => _openOrderDetail(order),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            children: col2.map((order) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: OrderQueueCard(
                  key: ValueKey('order_card_${order.id}'),
                  order: order,
                  now: widget.controller.now,
                  onStatusChanged: _handleStatusChanged,
                  onTap: () => _openOrderDetail(order),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
