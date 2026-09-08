import 'package:flutter/material.dart';
import '../order/order_detail_view.dart';
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
        _handleStatusChanged(order, targetStatus);
        return widget.controller.allOrders.firstWhere((o) => o.id == orderId);
      },
      reloadFn: (orderId) async {
        return widget.controller.allOrders.firstWhere((o) => o.id == orderId);
      },
    );
  }

  List<QueueOrder> _getOrdersForTab(int tabIndex) {
    final now = widget.controller.now;
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

    filtered.sort((a, b) {
      final aOverdue = a.isOverdueAt(now);
      final bOverdue = b.isOverdueAt(now);
      if (aOverdue && !bOverdue) return -1;
      if (!aOverdue && bOverdue) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });

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
          backgroundColor: const Color(0xFFF4F7F6),
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
    return Container(
      color: const Color(0xFF1B7C71),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 48),
                  const Expanded(
                    child: Text(
                      'Antrean Dapur',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('queue-refresh-button'),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    onPressed: widget.onRefresh ?? () => setState(() {}),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3.5,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.normal,
              ),
              tabs: const [
                Tab(text: 'Menunggu'),
                Tab(text: 'Diproses'),
                Tab(text: 'Siap'),
              ],
            ),
          ],
        ),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
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
