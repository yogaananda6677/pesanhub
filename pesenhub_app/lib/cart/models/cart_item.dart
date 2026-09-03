import '../../menu/models/menu_item.dart';

/// CartItem represents an item configured with modifiers in the cashier's active cart.
class CartItem {
  final String id;
  final MenuItem menuItem;
  final String modifierSummary;
  final Map<String, Set<String>> selectedOptionIds;
  final int quantity;
  final int unitPrice;
  final String notes;

  const CartItem({
    required this.id,
    required this.menuItem,
    required this.modifierSummary,
    required this.selectedOptionIds,
    required this.quantity,
    required this.unitPrice,
    this.notes = '',
  });

  int get lineTotal => unitPrice * quantity;
  bool get isDrink => menuItem.isDrink;

  CartItem copyWith({
    String? id,
    MenuItem? menuItem,
    String? modifierSummary,
    Map<String, Set<String>>? selectedOptionIds,
    int? quantity,
    int? unitPrice,
    String? notes,
  }) {
    return CartItem(
      id: id ?? this.id,
      menuItem: menuItem ?? this.menuItem,
      modifierSummary: modifierSummary ?? this.modifierSummary,
      selectedOptionIds: selectedOptionIds ?? this.selectedOptionIds,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      notes: notes ?? this.notes,
    );
  }
}
