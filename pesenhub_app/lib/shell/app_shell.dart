import 'package:flutter/material.dart';
import '../dashboard/dashboard_view.dart';
import '../dashboard/models/dashboard_state.dart';
import '../dashboard/models/operational_summary.dart';
import '../navigation/app_destination.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'destination_views.dart';

/// AppShell provides an adaptive, state-preserving navigation framework.
/// Fulfills Issue #24 and Issue #25 Acceptance Criteria.
class AppShell extends StatefulWidget {
  final int initialIndex;
  final DashboardState? initialDashboardState;
  final VoidCallback? onRefreshDashboard;

  const AppShell({
    super.key,
    this.initialIndex = 0,
    this.initialDashboardState,
    this.onRefreshDashboard,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex;
  final GlobalKey _contentStackKey = GlobalKey();
  late DashboardState _dashboardState;

  @override
  void initState() {
    super.initState();
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

  void _onDestinationSelected(int index) {
    if (index >= 0 && index < AppDestination.values.length) {
      setState(() {
        _selectedIndex = index;
      });
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
      const PosDestinationView(),
      const QueueDestinationView(),
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
          body: Row(
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
          bottomNavigationBar: isTablet
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onDestinationSelected,
                  backgroundColor: AppColors.surface,
                  indicatorColor: AppColors.primaryContainer,
                  elevation: 2,
                  destinations: AppDestination.values.map((d) {
                    return NavigationDestination(
                      icon: Icon(d.icon, color: AppColors.textSecondary),
                      selectedIcon: Icon(
                        d.selectedIcon,
                        color: AppColors.primary,
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
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.primaryContainer,
                extended: false,
                minWidth: 80,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Container(
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
                    icon: Icon(d.icon, color: AppColors.textSecondary),
                    selectedIcon: Icon(
                      d.selectedIcon,
                      color: AppColors.primary,
                    ),
                    label: Text(d.label, style: AppTypography.labelSmall),
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
            _buildConnectivityBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectivityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: AppSpacing.borderRadiusFull,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_rounded, size: 14, color: AppColors.success),
          SizedBox(width: AppSpacing.xs),
          Text(
            'Online',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
