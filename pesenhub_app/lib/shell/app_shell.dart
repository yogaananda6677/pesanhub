import 'package:flutter/material.dart';
import '../alerts/order_alert_controller.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/models/cart_order_draft.dart';
import '../connectivity/connectivity_controller.dart';
import '../dashboard/dashboard_view.dart';
import '../dashboard/models/dashboard_state.dart';
import '../dashboard/models/operational_summary.dart';
import '../navigation/app_destination.dart';
import '../queue/controllers/queue_controller.dart';
import '../queue/models/queue_order.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/connectivity_badge.dart';
import '../widgets/order_heads_up_alert.dart';
import 'destination_views.dart';

/// AppShell provides an adaptive, state-preserving navigation framework.
/// Fulfills Issue #24 and Issue #25 Acceptance Criteria.
class AppShell extends StatefulWidget {
  final int initialIndex;
  final DashboardState? initialDashboardState;
  final VoidCallback? onRefreshDashboard;
  final ConnectivityController? connectivityController;
  final OrderAlertController? alertController;
  final QueueController? queueController;
  final CartController? cartController;
  final Future<QueueOrder> Function(CartOrderDraft draft)? submitOrder;

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
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _primaryDestinations = [
    AppDestination.dashboard,
    AppDestination.pos,
    AppDestination.queue,
    AppDestination.kds,
  ];

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
        DashboardState.success(
          OperationalSummary(
            pendingCount: 3,
            preparingCount: 2,
            readyCount: 1,
            overdueCount: 1,
            completedCount: 18,
            pendingSyncCount: 0,
            lastUpdatedAt: DateTime.now(),
          ),
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _alerts.setLifecycle(state);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final destination = AppDestination.fromIndex(_selectedIndex);
    final primaryIndex = _primaryDestinations.indexOf(destination);
    return primaryIndex == -1 ? _primaryDestinations.length : primaryIndex;
  }

  void _onMobileDestinationSelected(int index) {
    if (index == _primaryDestinations.length) {
      _showMoreDestinations();
      return;
    }
    _onDestinationSelected(_primaryDestinations[index].index);
  }

  Future<void> _showMoreDestinations() async {
    final selected = await showModalBottomSheet<AppDestination>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            key: const Key('more-destinations-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Lainnya', style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Fitur sekunder outlet tetap tersedia tanpa memenuhi navigasi utama.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _MoreDestinationTile(
                destination: AppDestination.menu,
                selected: _selectedIndex == AppDestination.menu.index,
              ),
              const SizedBox(height: AppSpacing.sm),
              _MoreDestinationTile(
                destination: AppDestination.settings,
                selected: _selectedIndex == AppDestination.settings.index,
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      _onDestinationSelected(selected.index);
    }
  }

  void _handleRefreshDashboard() {
    if (widget.onRefreshDashboard != null) {
      widget.onRefreshDashboard!();
    } else {
      setState(() {
        _dashboardState = DashboardState.success(
          OperationalSummary(
            pendingCount: 3,
            preparingCount: 2,
            readyCount: 1,
            overdueCount: 1,
            completedCount: 18,
            pendingSyncCount: 0,
            lastUpdatedAt: DateTime.now(),
          ),
        );
      });
    }
  }

  List<Widget> _buildViews() {
    return [
      DashboardView(
        state: _dashboardState,
        onRefresh: _handleRefreshDashboard,
        onNavigateToPos: () => _onDestinationSelected(AppDestination.pos.index),
        onNavigateToQueue: () =>
            _onDestinationSelected(AppDestination.queue.index),
        onNavigateToKds: () => _onDestinationSelected(AppDestination.kds.index),
      ),
      PosDestinationView(
        cartController: widget.cartController,
        submitOrder: widget.submitOrder,
        onNavigateToQueue: () =>
            _onDestinationSelected(AppDestination.queue.index),
      ),
      QueueDestinationView(
        controller: widget.queueController,
        alertController: _alerts,
      ),
      const KdsDestinationView(),
      const MenuDestinationView(),
      const SettingsDestinationView(),
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
                  onDestinationSelected: _onMobileDestinationSelected,
                  destinations: [
                    ..._primaryDestinations.map((d) {
                      return NavigationDestination(
                        icon: Icon(d.icon, color: AppColors.textSecondary),
                        selectedIcon: Icon(
                          d.selectedIcon,
                          color: AppColors.primary,
                        ),
                        label: d.label,
                      );
                    }),
                    const NavigationDestination(
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: AppColors.textSecondary,
                      ),
                      selectedIcon: Icon(
                        Icons.more_horiz_rounded,
                        color: AppColors.primary,
                      ),
                      label: 'Lainnya',
                    ),
                  ],
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
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: AppSpacing.borderRadiusSm,
                    ),
                    child: const Icon(
                      Icons.rice_bowl_rounded,
                      color: AppColors.surface,
                      size: 24,
                    ),
                  ),
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showBrand) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(
                  Icons.rice_bowl_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    destination.title,
                    style: AppTypography.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'PesenHub Outlet #01 — Nasi Goreng',
                    style: AppTypography.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ConnectivityBadge(controller: _connectivity),
            const SizedBox(width: AppSpacing.xs),
            AnimatedBuilder(
              animation: _alerts,
              builder: (context, _) => IconButton(
                key: const Key('notification-permission-button'),
                tooltip: _alerts.permission == AlertPermission.denied
                    ? 'Notifikasi ditolak — alert tetap tampil di aplikasi'
                    : 'Aktifkan notifikasi',
                onPressed: _alerts.requestPermission,
                icon: Icon(
                  _alerts.permission == AlertPermission.granted
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreDestinationTile extends StatelessWidget {
  final AppDestination destination;
  final bool selected;

  const _MoreDestinationTile({
    required this.destination,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primaryContainer : AppColors.surfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: InkWell(
          key: Key('more-${destination.name}'),
          borderRadius: AppSpacing.borderRadiusMd,
          onTap: () => Navigator.of(context).pop(destination),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.minTouchTarget,
                  height: AppSpacing.minTouchTarget,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.surface,
                    borderRadius: AppSpacing.borderRadiusSm,
                  ),
                  child: Icon(
                    destination.selectedIcon,
                    color: selected ? AppColors.onPrimary : AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(destination.label, style: AppTypography.titleMedium),
                      Text(
                        destination == AppDestination.menu
                            ? 'Atur menu tersedia atau habis'
                            : 'Profil, perangkat, dan preferensi outlet',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.chevron_right,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
