import '../../menu/models/menu_item.dart';

/// CartItem represents an item configured with modifiers in the cashier's active cart.
class CartItem {
  final String id;
  final MenuItem menuItem;
  final String modifierSummary;
  final Map<String, Set<String>> selectedOptionIds;
  final Map<String, Map<String, int>> selectedOptionQuantities;
  final int quantity;
  final int unitPrice;
  final String notes;

  const CartItem({
    required this.id,
    required this.menuItem,
    required this.modifierSummary,
    required this.selectedOptionIds,
    this.selectedOptionQuantities = const {},
    required this.quantity,
    required this.unitPrice,
    this.notes = '',
  });

  int get lineTotal => unitPrice * quantity;
  bool get isDrink => menuItem.isDrink;

  /// Calculates total price delta from configured modifiers.
  int get modifierTotal {
    int total = 0;
    for (final group in menuItem.modifierGroups) {
      final quantities = selectedOptionQuantities[group.id];
      if (quantities != null) {
        for (final option in group.options) {
          final q = quantities[option.id] ?? 0;
          if (q > 0) {
            total += option.priceDeltaAmount * q;
          }
        }
      } else {
        final ids = selectedOptionIds[group.id];
        if (ids != null) {
          for (final option in group.options) {
            if (ids.contains(option.id)) {
              total += option.priceDeltaAmount;
            }
          }
        }
      }
    }
    return total;
  }

  /// Calculates the dynamic unit price for a given sales channel.
  int priceForChannel(String channel) {
    final basePrice = menuItem.priceForChannel(channel) ?? menuItem.priceAmount;
    return basePrice + modifierTotal;
  }

  CartItem copyWith({
    String? id,
    MenuItem? menuItem,
    String? modifierSummary,
    Map<String, Set<String>>? selectedOptionIds,
    Map<String, Map<String, int>>? selectedOptionQuantities,
    int? quantity,
    int? unitPrice,
    String? notes,
  }) {
    return CartItem(
      id: id ?? this.id,
      menuItem: menuItem ?? this.menuItem,
      modifierSummary: modifierSummary ?? this.modifierSummary,
      selectedOptionIds: selectedOptionIds ?? this.selectedOptionIds,
      selectedOptionQuantities:
          selectedOptionQuantities ?? this.selectedOptionQuantities,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      notes: notes ?? this.notes,
    );
  }
}
