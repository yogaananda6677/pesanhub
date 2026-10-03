import 'dart:async';

import 'package:flutter/material.dart';
import '../alerts/order_alert_controller.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/models/cart_order_draft.dart';
import '../connectivity/connectivity_controller.dart';
import '../dashboard/dashboard_view.dart';
import '../dashboard/models/dashboard_state.dart';
import '../dashboard/models/operational_summary.dart';
import '../menu/controllers/menu_availability_controller.dart';
import '../menu/controllers/menu_controller.dart' as mc;
import '../navigation/app_destination.dart';
import '../queue/controllers/queue_controller.dart';
import '../queue/models/queue_order.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/brand_logo.dart';
import '../widgets/order_heads_up_alert.dart';
import 'destination_views.dart';
import 'widgets/notification_sheet.dart';
import 'widgets/profile_sheet.dart';

/// AppShell provides an adaptive, state-preserving navigation framework.
/// Fulfills Issue #24 and Issue #25 Acceptance Criteria.
/// Simplified kitchen queue & navbar matching Issue #147.
class AppShell extends StatefulWidget {
  final int initialIndex;
  final DashboardState? initialDashboardState;
  final VoidCallback? onRefreshDashboard;
  final ConnectivityController? connectivityController;
  final OrderAlertController? alertController;
  final QueueController? queueController;
  final CartController? cartController;
  final Future<QueueOrder> Function(CartOrderDraft draft)? submitOrder;
  final Future<void> Function()? onSignOut;
  final mc.MenuController? menuController;
  final MenuAvailabilityController? menuManagementController;
  final bool isAdmin;
  final Future<String> Function(String email)? inviteCashier;
  final String? userName;
  final String? userEmail;
  final String? userRole;
  final String? branchName;
  final String? branchId;
  final List<Map<String, dynamic>>? availableBranches;
  final Future<void> Function(String? branchId)? onSwitchBranch;
  final FutureOr<void> Function(QueueOrder order, String newStatus)? onStatusChanged;
  final Future<void> Function()? onRefreshQueue;

  const AppShell({
    super.key,
    this.initialIndex = 0,
    this.initialDashboardState,
    this.onRefreshDashboard,
    this.connectivityController,
    this.alertController,
    this.queueController,
    this.cartController,
    this.submitOrder,
    this.onSignOut,
    this.menuController,
    this.menuManagementController,
    this.isAdmin = false,
    this.inviteCashier,
    this.userName,
    this.userEmail,
    this.userRole,
    this.branchName,
    this.branchId,
    this.availableBranches,
    this.onSwitchBranch,
    this.onStatusChanged,
    this.onRefreshQueue,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _selectedIndex;
  final GlobalKey _contentStackKey = GlobalKey();
  late DashboardState _dashboardState;
  late final ConnectivityController _connectivity;
  late final OrderAlertController _alerts;
  late final bool _ownsConnectivity;
  late final bool _ownsAlerts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsConnectivity = widget.connectivityController == null;
    _ownsAlerts = widget.alertController == null;
    _connectivity = widget.connectivityController ?? ConnectivityController();
    _alerts = widget.alertController ?? OrderAlertController();
    _connectivity.start();
    _alerts.initialize();
    _selectedIndex = widget.initialIndex;
    _dashboardState =
        widget.initialDashboardState ??
        DashboardState.success(_calculateSummary());
    widget.queueController?.addListener(_onQueueChanged);
  }

  OperationalSummary _calculateSummary() {
    final queue = widget.queueController;
    if (queue == null) {
      return OperationalSummary(lastUpdatedAt: DateTime.now());
    }
    int pending = 0;
    int preparing = 0;
    int ready = 0;
    int overdue = 0;
    int completed = 0;
    int totalRev = 0;
    final now = DateTime.now();
    for (final order in queue.allOrders) {
      if (order.orderStatus == 'COMPLETED' || order.paymentStatus == 'PAID') {
        totalRev += order.totalAmount;
      }
      switch (order.orderStatus) {
        case 'PENDING':
        case 'ACCEPTED':
          pending++;
          if (now.difference(order.createdAt).inMinutes > 15) {
            overdue++;
          }
          break;
        case 'PREPARING':
          preparing++;
          if (now.difference(order.createdAt).inMinutes > 20) {
            overdue++;
          }
          break;
        case 'READY_FOR_PICKUP':
        case 'READY':
          ready++;
          break;
        case 'COMPLETED':
          completed++;
          break;
      }
    }
    return OperationalSummary(
      pendingCount: pending,
      preparingCount: preparing,
      readyCount: ready,
      overdueCount: overdue,
      completedCount: completed,
      totalRevenue: totalRev,
      lastUpdatedAt: now,
    );
  }

  void _onQueueChanged() {
    if (widget.initialDashboardState == null && mounted) {
      setState(() {
        _dashboardState = DashboardState.success(_calculateSummary());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _alerts.setLifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.queueController?.removeListener(_onQueueChanged);
    if (_ownsConnectivity) _connectivity.dispose();
    if (_ownsAlerts) _alerts.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    if (index >= 0 && index < AppDestination.values.length) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  int get _mobileSelectedIndex {
    if (_selectedIndex >= 0 && _selectedIndex < AppDestination.values.length) {
      return _selectedIndex;
    }
    return 0;
  }

  void _handleRefreshDashboard() {
    if (widget.onRefreshDashboard != null) {
      widget.onRefreshDashboard!();
    } else {
      setState(() {
        _dashboardState = DashboardState.success(_calculateSummary());
      });
    }
  }

  void _openMenuManagement() {
    if (!widget.isAdmin) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'Kelola Ketersediaan Menu',
              style: AppTypography.titleMedium,
            ),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, color: AppColors.border),
            ),
          ),
          body: MenuDestinationView(
            menuController: widget.menuController,
            availabilityController: widget.menuManagementController,
            onRefresh: () => widget.menuManagementController?.onRefresh?.call(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildViews() {
    return [
      DashboardView(
        state: _dashboardState,
        onRefresh: _handleRefreshDashboard,
        onNavigateToPos: () => _onDestinationSelected(AppDestination.pos.index),
        onNavigateToQueue: () =>
            _onDestinationSelected(AppDestination.queue.index),
        onNavigateToMenu: widget.isAdmin ? _openMenuManagement : null,
        isOnline: _connectivity.state != OperationalConnectionState.offline,
        userName: widget.userName,
        queueController: widget.queueController,
      ),
      PosDestinationView(
        menuController: widget.menuController,
        cartController: widget.cartController,
        submitOrder: widget.submitOrder,
        connectivityController: _connectivity,
        onNavigateToQueue: () =>
            _onDestinationSelected(AppDestination.queue.index),
      ),
      QueueDestinationView(
        controller: widget.queueController,
        alertController: _alerts,
        onStatusChanged: widget.onStatusChanged,
        onRefresh: widget.onRefreshQueue,
      ),
      SettingsDestinationView(
        onSignOut: widget.onSignOut,
        isAdmin: widget.isAdmin,
        inviteCashier: widget.inviteCashier,
        userName: widget.userName,
        userEmail: widget.userEmail,
        userRole: widget.userRole,
        branchName: widget.branchName,
        connectivityController: _connectivity,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final destination = AppDestination.fromIndex(_selectedIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet =
            constraints.maxWidth >= AppSpacing.tabletBreakpoint;

        return Scaffold(
          backgroundColor: AppColors.background,
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              Row(
                children: [
                  if (isTablet) ...[
                    _buildNavigationRail(),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                  ],
                  Expanded(
                    child: Column(
                      children: [
                        _buildHeader(
                          destination: destination,
                          showBrand: !isTablet,
                        ),
                        Expanded(
                          child: IndexedStack(
                            key: _contentStackKey,
                            index: _selectedIndex,
                            children: _buildViews(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              AnimatedBuilder(
                animation: _alerts,
                builder: (context, _) {
                  final alert = _alerts.activeAlert;
                  if (alert == null) return const SizedBox.shrink();
                  return Positioned(
                    top: 8,
                    left: isTablet ? 96 : 12,
                    right: 12,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: OrderHeadsUpAlert(
                        alert: alert,
                        onDismiss: _alerts.dismiss,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: isTablet
              ? null
              : NavigationBar(
                  key: const Key('primary-bottom-navigation'),
                  selectedIndex: _mobileSelectedIndex,
                  onDestinationSelected: _onDestinationSelected,
                  destinations: AppDestination.values.map((d) {
                    return NavigationDestination(
                      icon: Icon(d.icon, color: AppColors.textSecondary),
                      selectedIcon: Icon(
                        d.selectedIcon,
                        color: const Color(0xFFE5573F),
                      ),
                      label: d.label,
                    );
                  }).toList(),
                ),
        );
      },
    );
  }

  Widget _buildNavigationRail() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onDestinationSelected,
                extended: false,
                minWidth: 88,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: BrandLogo(size: 40),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Tooltip(
                        message: 'Sistem Terhubung ke Server',
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: const BoxDecoration(
                            color: AppColors.successBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cloud_done_rounded,
                            color: AppColors.success,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                destinations: AppDestination.values.map((d) {
                  return NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader({
    required AppDestination destination,
    bool showBrand = true,
  }) {
    final subtitle = switch (destination) {
      AppDestination.dashboard => 'Ringkasan Operasional',
      AppDestination.pos => 'Sistem Pemesanan POS',
      AppDestination.queue => 'Manajemen Antrean',
      AppDestination.settings => 'Pengaturan Outlet',
    };
    final effectiveOnline =
        _connectivity.state != OperationalConnectionState.offline;
    final displayName = widget.userName?.trim().isNotEmpty == true
        ? widget.userName!.trim()
        : 'Yoga Ananda';
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'Y';
    final hasUnreadAlert = _alerts.activeAlert != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showBrand) ...[
              const BrandLogo(size: 34),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: const Text(
                          'Jenggirat',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Modern Navbar Online Status Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: effectiveOnline
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: effectiveOnline
                                ? const Color(0xFFC8E6C9)
                                : const Color(0xFFFFCDD2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              effectiveOnline
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_off_rounded,
                              size: 13,
                              color: effectiveOnline
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              effectiveOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: effectiveOnline
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFC62828),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (widget.isAdmin && widget.onSwitchBranch != null)
                    InkWell(
                      key: const Key('admin-branch-switcher-button'),
                      onTap: () => _showBranchSwitcherBottomSheet(context),
                      borderRadius: BorderRadius.circular(4),
                      child: Text(
                        '$subtitle • ${widget.branchName ?? "Semua Cabang"} ▾',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    Text(
                      '$subtitle • ${widget.branchName ?? "Cabang"}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (destination != AppDestination.queue)
                    SizedBox(
                      width: 0,
                      height: 0,
                      child: Text(
                        destination.title,
                        style: const TextStyle(
                          fontSize: 0,
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AnimatedBuilder(
              animation: _alerts,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      key: const Key('notification-permission-button'),
                      tooltip: 'Pusat Notifikasi & Alert Operasional',
                      onPressed: () {
                        if (_alerts.permission != AlertPermission.granted) {
                          _alerts.requestPermission();
                        }
                        NotificationSheet.show(
                          context,
                          alertController: _alerts,
                          activeOrders: widget.queueController?.allOrders,
                        );
                      },
                      icon: Icon(
                        _alerts.permission == AlertPermission.granted ||
                                hasUnreadAlert
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        color: hasUnreadAlert
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        size: 19,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  if (hasUnreadAlert)
                    Positioned(
                      top: 1,
                      right: 1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC62828),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // User avatar (interactive)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ProfileSheet.show(
                    context,
                    displayName: widget.userName,
                    email: widget.userEmail,
                    role: widget.isAdmin
                        ? 'Superadmin'
                        : (widget.userRole ?? 'Kasir Utama'),
                    branchName: widget.branchName,
                    onSignOut: widget.onSignOut,
                  );
                },
                borderRadius: BorderRadius.circular(18),
                child: Tooltip(
                  message: 'Profil Kasir & Informasi Gerai',
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFF0DCD3),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  void _showBranchSwitcherBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final branches = widget.availableBranches ?? [];
        final currentId = widget.branchId;

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Pilih Cabang Operasional',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pilih cabang untuk memfilter antrean pesanan dan katalog ketersediaan.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    key: const Key('branch-option-all'),
                    leading: const Icon(Icons.dashboard_customize_outlined, color: AppColors.primary),
                    title: const Text(
                      'Semua Cabang',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Tampilkan data gabungan seluruh cabang'),
                    trailing: currentId == null || currentId.isEmpty
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                        : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    selected: currentId == null || currentId.isEmpty,
                    selectedTileColor: AppColors.primaryContainer.withValues(alpha: 0.3),
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      widget.onSwitchBranch?.call(null);
                    },
                  ),
                  const Divider(),
                  ...branches.map((b) {
                    final id = b['id']?.toString() ?? '';
                    final name = b['name']?.toString() ?? 'Cabang';
                    final code = b['code']?.toString() ?? '';
                    final isSelected = currentId == id;

                    return ListTile(
                      key: Key('branch-option-$id'),
                      leading: const Icon(Icons.storefront_rounded, color: AppColors.primary),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('Kode: $code'),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                          : null,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      selected: isSelected,
                      selectedTileColor: AppColors.primaryContainer.withValues(alpha: 0.3),
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        widget.onSwitchBranch?.call(id);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
