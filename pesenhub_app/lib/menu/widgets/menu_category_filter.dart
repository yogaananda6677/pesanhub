import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/menu_category.dart';

/// MenuCategoryFilter provides horizontal category filter chips for fast scanning.
/// MenuCategoryFilter provides horizontal category tabs for fast scanning.
/// Styled according to POS design reference with minimum 48dp touch targets.
class MenuCategoryFilter extends StatelessWidget {
  final List<MenuCategory> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onSelectCategory;
  final int Function(String categoryId) countForCategory;

  const MenuCategoryFilter({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelectCategory,
    required this.countForCategory,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildChip('ALL', 'Semua'),
          _buildTab('ALL', 'Semua'),
          ...categories.where((c) => c.isActive).map((cat) {
            return Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: _buildChip(cat.id, cat.name),
              child: _buildTab(cat.id, cat.name),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChip(String id, String label) {
  Widget _buildTab(String id, String label) {
    final isSelected = selectedCategoryId == id;
    final count = countForCategory(id);

    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      selectedColor: AppColors.primaryContainer,
      checkmarkColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? AppColors.primary : AppColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusFull,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('category_tab_$id'),
        onTap: () => onSelectCategory(id),
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: 1.5,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Center(
                child: Text(
                  '$label ($count)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      onSelected: (_) => onSelectCategory(id),
    );
  }
}
