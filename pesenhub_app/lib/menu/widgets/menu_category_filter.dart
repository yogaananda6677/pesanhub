import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/menu_category.dart';

/// MenuCategoryFilter provides horizontal category filter chips for fast scanning.
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
      child: Row(
        children: [
          _buildChip('ALL', 'Semua'),
          ...categories.where((c) => c.isActive).map((cat) {
            return Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: _buildChip(cat.id, cat.name),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChip(String id, String label) {
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
        ),
      ),
      onSelected: (_) => onSelectCategory(id),
    );
  }
}
