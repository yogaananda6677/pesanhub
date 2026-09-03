import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_text_field.dart';
import 'controllers/menu_controller.dart' as mc;
import 'controllers/modifier_selection_state.dart';
import 'models/menu_item.dart';
import 'models/menu_state.dart';
import 'widgets/menu_category_filter.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/modifier_config_dialog.dart';

/// MenuCatalogView renders the full responsive catalog with search, category filtering, and modifier dialog.
/// Fulfills Issue #27 Acceptance Criteria #1, #2, #4, and #5.
class MenuCatalogView extends StatefulWidget {
  final mc.MenuController controller;
  final VoidCallback? onRefresh;
  final ValueChanged<ModifierSelectionState>? onItemConfigured;

  const MenuCatalogView({
    super.key,
    required this.controller,
    this.onRefresh,
    this.onItemConfigured,
  });

  @override
  State<MenuCatalogView> createState() => _MenuCatalogViewState();
}

class _MenuCatalogViewState extends State<MenuCatalogView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _searchController.text = widget.controller.searchQuery;
  }

  @override
  void didUpdateWidget(covariant MenuCatalogView oldWidget) {
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

  void _handleSelectItem(MenuItem item) async {
    if (!item.isAvailable) return;

    final result = await ModifierConfigDialog.show(
      context: context,
      item: item,
    );

    if (result != null && widget.onItemConfigured != null) {
      widget.onItemConfigured!(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    switch (state.status) {
      case MenuStatus.loading:
        return const Center(
          child: AppLoadingState(message: 'Memuat katalog menu...'),
        );

      case MenuStatus.error:
        return Center(
          child: AppErrorState(
            message: state.errorMessage ?? 'Gagal memuat katalog menu.',
            onRetry: widget.onRefresh,
          ),
        );

      case MenuStatus.empty:
      case MenuStatus.success:
        return _buildContent(context, state);
    }
  }

  Widget _buildContent(BuildContext context, MenuState state) {
    final filteredItems = widget.controller.filteredMenus;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 720;
        final int crossAxisCount = isWide ? 3 : 2;
        final double childAspectRatio = isWide ? 1.05 : 0.85;

        return SingleChildScrollView(
          key: const PageStorageKey('menu_catalog_scroll'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Search Bar with Debounce
              AppTextField(
                controller: _searchController,
                hintText: 'Cari menu (Nasi Goreng, Es Teh, SKU)...',
                prefixIcon: const Icon(Icons.search_rounded),
                onChanged: (val) => widget.controller.onSearchChanged(val),
              ),
              const SizedBox(height: AppSpacing.sm),

              // 2. Category Filter Chips
              MenuCategoryFilter(
                categories: widget.controller.categories,
                selectedCategoryId: widget.controller.selectedCategoryId,
                onSelectCategory: widget.controller.selectCategory,
                countForCategory: widget.controller.countForCategory,
              ),
              const SizedBox(height: AppSpacing.lg),

              // 3. Menu Grid or Empty State
              if (filteredItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: AppEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Menu Tidak Ditemukan',
                    description:
                        'Coba ubah kata kunci pencarian atau ganti kategori.',
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return MenuItemCard(
                      key: ValueKey('menu_card_${item.id}'),
                      item: item,
                      onSelect: _handleSelectItem,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
