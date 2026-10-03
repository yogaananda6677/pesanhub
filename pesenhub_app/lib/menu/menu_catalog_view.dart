import 'package:flutter/material.dart';
import '../connectivity/connectivity_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_text_field.dart';
import '../widgets/connectivity_badge.dart';
import 'controllers/menu_controller.dart' as mc;
import 'controllers/modifier_selection_state.dart';
import 'models/menu_item.dart';
import 'models/menu_state.dart';
import 'widgets/menu_category_filter.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/modifier_config_dialog.dart';

/// MenuCatalogView renders the full responsive catalog with search, category filtering, and modifier dialog.
/// Fulfills Issue #27 and Issue #133 Acceptance Criteria.
class MenuCatalogView extends StatefulWidget {
  final mc.MenuController controller;
  final VoidCallback? onRefresh;
  final ValueChanged<ModifierSelectionState>? onItemConfigured;
  final ConnectivityController? connectivityController;
  final EdgeInsets? contentPadding;

  const MenuCatalogView({
    super.key,
    required this.controller,
    this.onRefresh,
    this.onItemConfigured,
    this.connectivityController,
    this.contentPadding,
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
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final highTextScale = textScale > 1.3;
        final int crossAxisCount = highTextScale
            ? (isWide ? 2 : 1)
            : (isWide ? 3 : 2);
        final double cardExtent = highTextScale ? 286 : (isWide ? 220 : 190);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Pinned Sticky Header: Search Bar & Horizontal Category Tabs
            Container(
              color: AppColors.background,
              padding: EdgeInsets.fromLTRB(
                widget.contentPadding?.left ?? AppSpacing.lg,
                8,
                widget.contentPadding?.right ?? AppSpacing.lg,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSearchField(),
                  if (widget.connectivityController != null)
                    Opacity(
                      opacity: 0.0,
                      child: SizedBox(
                        width: 0,
                        height: 0,
                        child: ConnectivityBadge(
                          controller: widget.connectivityController!,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  MenuCategoryFilter(
                    categories: widget.controller.categories,
                    selectedCategoryId: widget.controller.selectedCategoryId,
                    onSelectCategory: widget.controller.selectCategory,
                    countForCategory: widget.controller.countForCategory,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEFE8E1)),

            // 2. Scrollable Menu Catalog Items
            Expanded(
              child: SingleChildScrollView(
                key: const PageStorageKey('menu_catalog_scroll'),
                padding: EdgeInsets.fromLTRB(
                  widget.contentPadding?.left ?? AppSpacing.lg,
                  8,
                  widget.contentPadding?.right ?? AppSpacing.lg,
                  widget.contentPadding?.bottom ?? AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Menu Grid or Empty State
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
                    else if (widget.controller.selectedCategoryId == 'ALL' &&
                        widget.controller.searchQuery.isEmpty)
                      _buildGroupedSectionView(
                        context,
                        filteredItems,
                        isWide: isWide,
                        crossAxisCount: crossAxisCount,
                        cardExtent: cardExtent,
                      )
                    else if (!isWide)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return MenuItemCard(
                            key: ValueKey('menu_card_${item.id}'),
                            item: item,
                            categoryName: _getCategoryName(item.categoryId),
                            compact: true,
                            onSelect: _handleSelectItem,
                          );
                        },
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: AppSpacing.md,
                          mainAxisSpacing: AppSpacing.md,
                          mainAxisExtent: cardExtent,
                        ),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return MenuItemCard(
                            key: ValueKey('menu_card_${item.id}'),
                            item: item,
                            categoryName: _getCategoryName(item.categoryId),
                            onSelect: _handleSelectItem,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupedSectionView(
    BuildContext context,
    List<MenuItem> items, {
    required bool isWide,
    required int crossAxisCount,
    required double cardExtent,
  }) {
    final Map<String, List<MenuItem>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.categoryId, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getCategoryName(entry.key) ?? 'Menu',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2B1B16),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5EBE6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entry.value.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!isWide)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entry.value.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = entry.value[index];
                return MenuItemCard(
                  key: ValueKey('menu_card_${item.id}'),
                  item: item,
                  categoryName: _getCategoryName(item.categoryId),
                  compact: true,
                  onSelect: _handleSelectItem,
                );
              },
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                mainAxisExtent: cardExtent,
              ),
              itemCount: entry.value.length,
              itemBuilder: (context, index) {
                final item = entry.value[index];
                return MenuItemCard(
                  key: ValueKey('menu_card_${item.id}'),
                  item: item,
                  categoryName: _getCategoryName(item.categoryId),
                  onSelect: _handleSelectItem,
                );
              },
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSearchField() {
    return AppTextField(
      controller: _searchController,
      hintText: 'Cari menu (Martabak, Terang Bulan, SKU)...',
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: _searchController.text.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Hapus pencarian',
              onPressed: () {
                _searchController.clear();
                widget.controller.onSearchChanged('');
                setState(() {});
              },
            )
          : null,
      onChanged: (value) {
        widget.controller.onSearchChanged(value);
        setState(() {});
      },
    );
  }

  String? _getCategoryName(String categoryId) {
    for (final cat in widget.controller.categories) {
      if (cat.id == categoryId) return cat.name;
    }
    return null;
  }
}
