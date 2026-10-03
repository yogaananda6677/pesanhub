import 'dart:async';

import 'package:flutter/material.dart';
import '../order/order_detail_view.dart';
import '../order/widgets/payment_dialog.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_feedback.dart';
import 'controllers/queue_controller.dart';
import 'models/queue_order.dart';
import 'models/queue_state.dart';
import 'widgets/order_queue_card.dart';

/// QueueView renders the streamlined kitchen queue with tabs: Menunggu, Diproses, Siap.
/// Fulfills Issue #147: Redesign Antrean Dapur.
class QueueView extends StatefulWidget {
  final QueueController controller;
  final VoidCallback? onRefresh;
  final FutureOr<void> Function(QueueOrder order, String newStatus)? onStatusChanged;

  const QueueView({
    super.key,
    required this.controller,
    this.onRefresh,
    this.onStatusChanged,
  });

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _tabController.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handlePaymentAndCompletion(QueueOrder order) async {
    final result = await PaymentDialog.show(
      context: context,
      totalAmount: order.totalAmount,
      orderNumber: order.orderNumber,
      customerName: order.customerName,
    );
    if (result != null && result.isPaid) {
      widget.controller.updatePaymentStatus(order.id, 'PAID');
      final currentOrder = widget.controller.allOrders.firstWhere(
        (o) => o.id == order.id,
        orElse: () => order.copyWith(paymentStatus: 'PAID'),
      );
      await _handleStatusChanged(currentOrder, 'COMPLETED');
    } else {
      if (mounted) {
        AppFeedback.show(
          context,
          message:
              'Pesanan belum dibayar. Selesaikan pembayaran terlebih dahulu sebelum menyelesaikan pesanan.',
          type: AppBannerType.warning,
        );
      }
    }
  }

  Future<void> _handlePayOrder(QueueOrder order) async {
    final result = await PaymentDialog.show(
      context: context,
      totalAmount: order.totalAmount,
      orderNumber: order.orderNumber,
      customerName: order.customerName,
    );
    if (result != null && result.isPaid) {
      final updated = widget.controller.updatePaymentStatus(order.id, 'PAID');
      if (mounted) {
        setState(() {});
        AppFeedback.show(
          context,
          message: updated
              ? 'Pembayaran ${order.orderNumber} berhasil dicatat (LUNAS).'
              : 'Gagal memperbarui status pembayaran.',
          type: updated ? AppBannerType.success : AppBannerType.error,
        );
      }
    }
  }

  Future<void> _handleStatusChanged(QueueOrder order, String newStatus) async {
    final currentOrder = widget.controller.allOrders.firstWhere(
      (o) => o.id == order.id,
      orElse: () => order,
    );

    if (newStatus == 'COMPLETED' && currentOrder.paymentStatus != 'PAID') {
      await _handlePaymentAndCompletion(currentOrder);
      return;
    }

    var updated = true;
    if (widget.onStatusChanged != null) {
      try {
        await widget.onStatusChanged!(currentOrder, newStatus);
      } catch (_) {
        updated = false;
      }
    } else {
      updated = widget.controller.updateOrderStatus(currentOrder.id, newStatus);
    }
    if (mounted) {
      setState(() {});
      AppFeedback.show(
        context,
        message: updated
            ? '${currentOrder.orderNumber} dipindahkan ke ${_statusLabel(newStatus)}.'
            : '${currentOrder.orderNumber} tidak dapat diperbarui. Muat ulang lalu coba lagi.',
        type: updated ? AppBannerType.success : AppBannerType.error,
      );
    }
  }

  String _statusLabel(String status) => switch (status) {
    'ACCEPTED' => 'Diterima',
    'PREPARING' => 'Diproses',
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
        final current = widget.controller.allOrders.firstWhere(
          (o) => o.id == orderId,
          orElse: () => order,
        );
        await _handleStatusChanged(current, targetStatus);
        return widget.controller.allOrders.firstWhere((o) => o.id == orderId);
      },
      reloadFn: (orderId) async {
        return widget.controller.allOrders.firstWhere((o) => o.id == orderId);
      },
    );
  }

  List<QueueOrder> _getOrdersForTab(int tabIndex) {
    final query = widget.controller.searchQuery.trim().toLowerCase();
    final source = widget.controller.sourceFilter;

    final filtered = widget.controller.allOrders.where((order) {
      final matchesStatus = switch (tabIndex) {
        0 => order.orderStatus == 'PENDING' || order.orderStatus == 'ACCEPTED',
        1 => order.orderStatus == 'PREPARING',
        2 => order.orderStatus == 'READY_FOR_PICKUP',
        _ => order.isActive,
      };
      if (!matchesStatus) return false;

      if (source != 'ALL' && order.source != source) return false;

      if (query.isNotEmpty) {
        final matchesNumber = order.orderNumber.toLowerCase().contains(query);
        final matchesName = order.customerName.toLowerCase().contains(query);
        if (!matchesNumber && !matchesName) return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    if (state.status == QueueStatus.loading) {
      return const Center(
        child: AppLoadingState(message: 'Memuat antrean pesanan...'),
      );
    }

    if (state.status == QueueStatus.error) {
      return Center(
        child: AppErrorState(
          message: state.errorMessage ?? 'Gagal memuat antrean pesanan.',
          onRetry: widget.onRefresh,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet =
            constraints.maxWidth >= AppSpacing.tabletBreakpoint;

        return Scaffold(
          backgroundColor: const Color(0xFFFBF9F6),
          body: Column(
            children: [
              _buildTopHeader(context),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTabContent(0, isTablet),
                    _buildTabContent(1, isTablet),
                    _buildTabContent(2, isTablet),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final counts = List<int>.generate(
      3,
      (index) => _getOrdersForTab(index).length,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        children: [
          const SizedBox(width: 0, height: 0, child: Text('Antrean Dapur')),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EEE7),
              borderRadius: BorderRadius.circular(13),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: const Color(0xFFE5573F),
              unselectedLabelColor: const Color(0xFF81736D),
              labelPadding: EdgeInsets.zero,
              tabs: [
                _queueTab('Menunggu', counts[0]),
                _queueTab('Diproses', counts[1]),
                _queueTab('Siap', counts[2]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueTab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 5),
          Container(
            constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFF1E9E2),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(int tabIndex, bool isTablet) {
    final orders = _getOrdersForTab(tabIndex);
    final state = widget.controller.state;

    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => widget.onRefresh?.call(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xxl,
          ),
          child: AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Tidak Ada Pesanan',
            description: switch (tabIndex) {
              0 => 'Belum ada pesanan yang menunggu diproses.',
              1 => 'Tidak ada pesanan yang sedang dimasak.',
              2 => 'Tidak ada pesanan yang siap diambil.',
              _ => 'Tidak ada pesanan.',
            },
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh?.call(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            if (isTablet)
              _buildTabletOrderGrid(orders)
            else
              _buildMobileOrderList(orders),
          ],
        ),
      ),
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
          onPayOrder: _handlePayOrder,
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
                  onPayOrder: _handlePayOrder,
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
                  onPayOrder: _handlePayOrder,
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
