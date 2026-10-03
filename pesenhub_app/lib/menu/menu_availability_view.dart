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
import 'widgets/catalog_editor_dialog.dart';

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
            onRetry: widget.onRefresh ?? widget.controller.onRefresh,
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
        final cardExtent = (430 + ((textScale - 1).clamp(0, 1) * 120))
            .toDouble();

        return SingleChildScrollView(
          padding: EdgeInsets.all(isTablet ? AppSpacing.xl : AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Role Info & Freshness Bar
              _buildRoleHeader(controller),
              const SizedBox(height: AppSpacing.md),

              if (controller.isOffline) ...[
                AppBanner(
                  message:
                      'Mode offline — katalog cache tetap tersedia, perubahan ditahan sampai backend terhubung.',
                  type: AppBannerType.warning,
                ),
                const SizedBox(height: AppSpacing.md),
              ],

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

              // 2. Action Buttons: Add Menu (Hero), Quick Actions Row
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        controller.mutationEnabled &&
                            controller.categories.any((item) => item.isActive)
                        ? () => showMenuEditor(context, controller: controller)
                        : null,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Tambah menu',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: controller.mutationEnabled
                              ? () => showGlobalExtraEditor(
                                  context,
                                  controller: controller,
                                )
                              : null,
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text(
                            'Kelola topping global',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: controller.mutationEnabled
                              ? () => _showCategoryManager(context, controller)
                              : null,
                          icon: const Icon(Icons.category_outlined, size: 16),
                          label: const Text(
                            'Kelola kategori',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: widget.onRefresh ?? controller.onRefresh,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'Muat ulang',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

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
                      isMutationEnabled: controller.mutationEnabled,
                      isUpdating: controller.updatingMenuIds.contains(item.id),
                      onToggle: (newVal) =>
                          _toggleAvailability(item.id, item.name, newVal),
                      onEdit: () => showMenuEditor(
                        context,
                        controller: controller,
                        menu: item,
                      ),
                      onEditPrice: () => showPriceEditor(
                        context,
                        controller: controller,
                        menu: item,
                      ),
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
                      isMutationEnabled: controller.mutationEnabled,
                      isUpdating: controller.updatingMenuIds.contains(item.id),
                      onToggle: (newVal) =>
                          _toggleAvailability(item.id, item.name, newVal),
                      onEdit: () => showMenuEditor(
                        context,
                        controller: controller,
                        menu: item,
                      ),
                      onEditPrice: () => showPriceEditor(
                        context,
                        controller: controller,
                        menu: item,
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCategoryManager(
    BuildContext context,
    MenuAvailabilityController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Kategori menu',
                      style: AppTypography.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const Key('add-category'),
                    tooltip: 'Tambah kategori',
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await showCategoryEditor(context, controller: controller);
                    },
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: controller.categories
                      .map(
                        (category) => ListTile(
                          title: Text(category.name),
                          subtitle: Text(
                            'Urutan ${category.sortOrder} • v${category.version} • ${category.isActive ? "Aktif" : "Nonaktif"}',
                          ),
                          trailing: IconButton(
                            key: Key('edit-category-${category.id}'),
                            tooltip: 'Edit kategori',
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              await showCategoryEditor(
                                context,
                                controller: controller,
                                category: category,
                              );
                            },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleHeader(MenuAvailabilityController controller) {
    final cachedAt = controller.cachedAt?.toLocal();
    final freshness = cachedAt == null
        ? 'Belum pernah tersinkron'
        : 'Diperbarui ${cachedAt.hour.toString().padLeft(2, "0")}:${cachedAt.minute.toString().padLeft(2, "0")}';

    final role = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: controller.isStaff
                ? const Color(0xFFF1F5F9)
                : AppColors.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(
              color: controller.isStaff
                  ? const Color(0xFFE2E8F0)
                  : AppColors.border,
            ),
          ),
          child: Icon(
            controller.isStaff
                ? Icons.admin_panel_settings_rounded
                : Icons.visibility_rounded,
            size: 22,
            color: controller.isStaff
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.isStaff
                    ? 'Pengelolaan Menu'
                    : 'Mode Pantau (${controller.role})',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: controller.isStaff
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    freshness,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final access = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: controller.mutationEnabled
            ? const Color(0xFFEBF7EE)
            : controller.isOffline
            ? const Color(0xFFFFF4E5)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: controller.mutationEnabled
              ? const Color(0xFFBCE3C5)
              : controller.isOffline
              ? const Color(0xFFFFD8A8)
              : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: controller.mutationEnabled
                  ? const Color(0xFF2E7D32)
                  : controller.isOffline
                  ? const Color(0xFFB25E09)
                  : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            controller.mutationEnabled
                ? 'Siap diubah'
                : controller.isOffline
                ? 'Offline • Hanya Baca'
                : 'Hanya Baca',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: controller.mutationEnabled
                  ? const Color(0xFF2E7D32)
                  : controller.isOffline
                  ? const Color(0xFFB25E09)
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEFE8E4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
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
      ),
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
            selectedColor: const Color(0xFF2E7D32),
            onTap: () => controller.setStatusFilter('AVAILABLE'),
          ),
          const SizedBox(width: AppSpacing.xs),
          _buildFilterChip(
            label: 'Habis',
            count: controller.unavailableCount,
            isSelected: controller.statusFilter == 'UNAVAILABLE',
            selectedColor: const Color(0xFFD32F2F),
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
    final isSemua = label == 'Semua';
    final activeColor = selectedColor ?? (isSemua ? const Color(0xFF2B1B16) : AppColors.primary);

    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: isSemua ? const Color(0xFF2B1B16) : activeColor.withValues(alpha: 0.12),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        color: isSelected
            ? (isSemua ? Colors.white : activeColor)
            : AppColors.textSecondary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? activeColor : const Color(0xFFE2E8F0),
          width: isSelected ? 1.4 : 1,
        ),
      ),
    );
  }
}
