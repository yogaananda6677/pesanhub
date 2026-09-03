import 'menu_modifier_group.dart';

/// MenuItem represents a catalog menu offering.
/// Conforms to pesenhub_be/internal/catalog Menu schema.
class MenuItem {
  final String id;
  final String categoryId;
  final String sku;
  final String name;
  final String? description;
  final int priceAmount;
  final bool isAvailable;
  final int version;
  final int sortOrder;
  final List<MenuModifierGroup> modifierGroups;
  final bool isDrink;

  const MenuItem({
    required this.id,
    required this.categoryId,
    required this.sku,
    required this.name,
    this.description,
    required this.priceAmount,
    this.isAvailable = true,
    this.version = 1,
    this.sortOrder = 0,
    this.modifierGroups = const [],
    this.isDrink = false,
  });

  /// True if item has customizable modifier groups.
  bool get hasModifiers => modifierGroups.isNotEmpty;

  /// Returns active modifier groups.
  List<MenuModifierGroup> get activeModifierGroups =>
      modifierGroups.where((g) => g.isActive).toList();

  MenuItem copyWith({
    String? id,
    String? categoryId,
    String? sku,
    String? name,
    String? description,
    int? priceAmount,
    bool? isAvailable,
    int? version,
    int? sortOrder,
    List<MenuModifierGroup>? modifierGroups,
    bool? isDrink,
  }) {
    return MenuItem(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      description: description ?? this.description,
      priceAmount: priceAmount ?? this.priceAmount,
      isAvailable: isAvailable ?? this.isAvailable,
      version: version ?? this.version,
      sortOrder: sortOrder ?? this.sortOrder,
      modifierGroups: modifierGroups ?? this.modifierGroups,
      isDrink: isDrink ?? this.isDrink,
    );
  }
}
