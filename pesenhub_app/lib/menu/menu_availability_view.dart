import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/app_text_field.dart';
import 'controllers/menu_availability_controller.dart';
import 'models/menu_state.dart';
import 'widgets/menu_availability_card.dart';
import 'widgets/menu_category_filter.dart';

/// MenuAvailabilityView provides an operational screen for managing menu availability
/// with role guards, optimistic toggles, rollback feedback, and responsive layout.
/// Fulfills Issue #31 Acceptance Criteria #1, #2, #3, and #5.
class MenuAvailabilityView extends StatefulWidget {
  final MenuAvailabilityController controller;
  final VoidCallback? onRefresh;

  const MenuAvailabilityView({
    super.key,
    required this.controller,
    this.onRefresh,
  });

  @override
  State<MenuAvailabilityView> createState() => _MenuAvailabilityViewState();
}

class _MenuAvailabilityViewState extends State<MenuAvailabilityView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _searchController.text = widget.controller.searchQuery;
  }

  @override
  void didUpdateWidget(covariant MenuAvailabilityView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleAvailability(
    String menuId,
    String menuName,
    bool targetAvailable,
  ) async {
    final success = await widget.controller.toggleAvailability(menuId);
    if (!mounted) return;
    AppFeedback.show(
      context,
      message: success
          ? '$menuName berhasil diperbarui menjadi ${targetAvailable ? "Tersedia" : "Habis"}.'
          : widget.controller.bannerMessage ??
                '$menuName gagal diperbarui. Coba lagi.',
      type: success ? AppBannerType.success : AppBannerType.error,
    );
  }

  String _getCategoryName(String categoryId) {
    for (final cat in widget.controller.categories) {
      if (cat.id == categoryId) return cat.name;
    }
    return 'Lainnya';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    switch (state.status) {
      case MenuStatus.loading:
        return const Center(
          child: AppLoadingState(message: 'Memuat data ketersediaan menu...'),
        );

      case MenuStatus.error:
        return Center(
          child: AppErrorState(
            message: state.errorMessage ?? 'Gagal memuat ketersediaan menu.',
            onRetry: widget.onRefresh,
          ),
        );

      case MenuStatus.empty:
      case MenuStatus.success:
        return _buildContent(context);
    }
  }

  Widget _buildContent(BuildContext context) {
    final controller = widget.controller;
    final filteredItems = controller.filteredMenus;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet = constraints.maxWidth >= 600;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final cardExtent = (196 + ((textScale - 1).clamp(0, 1) * 104))
            .toDouble();

        return SingleChildScrollView(
          padding: EdgeInsets.all(isTablet ? AppSpacing.xl : AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Role Info & Freshness Bar
              _buildRoleHeader(controller),
              const SizedBox(height: AppSpacing.md),

              // 2. Action / Error Feedback Banner
              if (controller.bannerMessage != null) ...[
                AppBanner(
                  message: controller.bannerMessage!,
                  type: controller.isBannerError
                      ? AppBannerType.error
                      : AppBannerType.success,
                  onClose: () => controller.clearBanner(),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 3. Search Bar
              AppTextField(
                controller: _searchController,
                hintText: 'Cari nama menu atau kode SKU...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          controller.onSearchChanged('', immediate: true);
                        },
                      )
                    : null,
                onChanged: (val) => controller.onSearchChanged(val),
              ),
              const SizedBox(height: AppSpacing.md),

              // 4. Status Filter Chips (Semua, Tersedia, Habis)
              _buildStatusFilterBar(controller),
              const SizedBox(height: AppSpacing.sm),

              // 5. Category Filter Chips
              if (controller.categories.isNotEmpty)
                MenuCategoryFilter(
                  categories: controller.categories,
                  selectedCategoryId: controller.selectedCategoryId,
                  onSelectCategory: (catId) => controller.selectCategory(catId),
                  countForCategory: (catId) {
                    if (catId == 'ALL') return controller.totalCount;
                    return controller.allMenus
                        .where((m) => m.categoryId == catId)
                        .length;
                  },
                ),
              const SizedBox(height: AppSpacing.md),

              // 6. Menu Items List / Grid
              if (filteredItems.isEmpty)
                const AppEmptyState(
                  title: 'Tidak Ada Menu Ditemukan',
                  description:
                      'Tidak ada menu yang sesuai dengan filter atau kata kunci pencarian.',
                  icon: Icons.search_off_rounded,
                )
              else if (isTablet)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    mainAxisExtent: cardExtent,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return MenuAvailabilityCard(
                      item: item,
                      categoryName: _getCategoryName(item.categoryId),
                      isStaff: controller.isStaff,
                      isUpdating: controller.updatingMenuIds.contains(item.id),
                      onToggle: (newVal) =>
                          _toggleAvailability(item.id, item.name, newVal),
                    );
                  },
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredItems.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return MenuAvailabilityCard(
                      item: item,
                      categoryName: _getCategoryName(item.categoryId),
                      isStaff: controller.isStaff,
                      isUpdating: controller.updatingMenuIds.contains(item.id),
                      onToggle: (newVal) =>
                          _toggleAvailability(item.id, item.name, newVal),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleHeader(MenuAvailabilityController controller) {
    final role = Row(
      children: [
        Icon(
          controller.isStaff
              ? Icons.admin_panel_settings_rounded
              : Icons.visibility_rounded,
          size: 20,
          color: controller.isStaff ? AppColors.primary : AppColors.textMuted,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            controller.isStaff
                ? 'Pengelolaan Menu (Staf Aktif)'
                : 'Mode Pantau (${controller.role})',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: controller.isStaff
                  ? AppColors.textPrimary
                  : AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
    final access = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: controller.isStaff
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.surfaceVariant,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: controller.isStaff
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Text(
        controller.isStaff ? 'Hak Ubah Aktif' : 'Hanya Baca',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: controller.isStaff ? AppColors.primary : AppColors.textMuted,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              role,
              const SizedBox(height: AppSpacing.sm),
              access,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: role),
            const SizedBox(width: AppSpacing.sm),
            access,
          ],
        );
      },
    );
  }

  Widget _buildStatusFilterBar(MenuAvailabilityController controller) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(
            label: 'Semua',
            count: controller.totalCount,
            isSelected: controller.statusFilter == 'ALL',
            onTap: () => controller.setStatusFilter('ALL'),
          ),
          const SizedBox(width: AppSpacing.xs),
          _buildFilterChip(
            label: 'Tersedia',
            count: controller.availableCount,
            isSelected: controller.statusFilter == 'AVAILABLE',
            selectedColor: AppColors.success,
            onTap: () => controller.setStatusFilter('AVAILABLE'),
          ),
          const SizedBox(width: AppSpacing.xs),
          _buildFilterChip(
            label: 'Habis',
            count: controller.unavailableCount,
            isSelected: controller.statusFilter == 'UNAVAILABLE',
            selectedColor: AppColors.error,
            onTap: () => controller.setStatusFilter('UNAVAILABLE'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required int count,
    required bool isSelected,
    Color? selectedColor,
    required VoidCallback onTap,
  }) {
    final activeColor = selectedColor ?? AppColors.primary;

    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: activeColor.withValues(alpha: 0.15),
      checkmarkColor: activeColor,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? activeColor : AppColors.textSecondary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusSm,
        side: BorderSide(color: isSelected ? activeColor : AppColors.border),
      ),
    );
  }
}
