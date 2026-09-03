import 'package:flutter/material.dart';
import '../navigation/app_destination.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'destination_views.dart';

/// AppShell provides an adaptive, state-preserving navigation framework.
/// Fulfills Issue #24 Acceptance Criteria #1, #2, #3, and #4.
class AppShell extends StatefulWidget {
  final int initialIndex;

  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex;
  final GlobalKey _contentStackKey = GlobalKey();

  // Static list of destination views to be held in IndexedStack for state retention
  static const List<Widget> _views = [
    PosDestinationView(),
    QueueDestinationView(),
    KdsDestinationView(),
    MenuDestinationView(),
    SettingsDestinationView(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  void _onDestinationSelected(int index) {
    if (index >= 0 && index < AppDestination.values.length) {
      setState(() {
        _selectedIndex = index;
      });
    }
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
                        children: _views,
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
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryContainer,
      extended: false,
      minWidth: 80,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          child: const Icon(
            Icons.rice_bowl_rounded,
            color: AppColors.primary,
            size: 28,
          ),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
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
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
      destinations: AppDestination.values.map((d) {
        return NavigationRailDestination(
          icon: Icon(d.icon, color: AppColors.textSecondary),
          selectedIcon: Icon(d.selectedIcon, color: AppColors.primary),
          label: Text(d.label, style: AppTypography.labelSmall),
        );
      }).toList(),
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
