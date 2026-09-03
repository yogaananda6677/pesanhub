import 'menu_option.dart';

/// MenuModifierGroup represents a group of modifier options with constraints.
/// Conforms to pesenhub_be/internal/catalog Group schema.
class MenuModifierGroup {
  final String id;
  final String code;
  final String name;
  final int minSelect;
  final int maxSelect;
  final int sortOrder;
  final bool isActive;
  final List<MenuOption> options;

  const MenuModifierGroup({
    required this.id,
    required this.code,
    required this.name,
    this.minSelect = 0,
    this.maxSelect = 1,
    this.sortOrder = 0,
    this.isActive = true,
    this.options = const [],
  });

  /// True if selecting at least one option is required.
  bool get isRequired => minSelect >= 1;

  /// True if only at most one option can be selected.
  bool get isSingleSelect => maxSelect == 1;
}
