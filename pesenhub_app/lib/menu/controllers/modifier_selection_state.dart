import 'package:flutter/foundation.dart';
import '../../cart/models/cart_item.dart';
import '../models/menu_item.dart';
import '../models/menu_modifier_group.dart';
import '../models/menu_option.dart';

/// ModifierSelectionState manages modifier selections, quantity, and price calculation for a menu item.
/// Fulfills Issue #27 Acceptance Criteria #2 and #3.
class ModifierSelectionState extends ChangeNotifier {
  final MenuItem menuItem;
  int _quantity = 1;
  final Map<String, Map<String, int>> _selectedOptionQuantities = {};
  String _notes = '';

  ModifierSelectionState({
    required this.menuItem,
    int initialQuantity = 1,
    Map<String, Map<String, int>>? initialSelectedOptions,
    String? initialNotes,
  }) {
    _quantity = initialQuantity < 1 ? 1 : initialQuantity;
    if (initialNotes != null) {
      _notes = initialNotes;
    }
    if (initialSelectedOptions != null && initialSelectedOptions.isNotEmpty) {
      for (final entry in initialSelectedOptions.entries) {
        _selectedOptionQuantities[entry.key] = Map<String, int>.from(
          entry.value,
        );
      }
    } else {
      _initializeDefaults();
    }
  }

  factory ModifierSelectionState.fromCartItem(CartItem item) {
    final Map<String, Map<String, int>> initialOptions = {};
    if (item.selectedOptionQuantities.isNotEmpty) {
      for (final entry in item.selectedOptionQuantities.entries) {
        initialOptions[entry.key] = Map<String, int>.from(entry.value);
      }
    } else if (item.selectedOptionIds.isNotEmpty) {
      for (final entry in item.selectedOptionIds.entries) {
        initialOptions[entry.key] = {for (final optId in entry.value) optId: 1};
      }
    }

    return ModifierSelectionState(
      menuItem: item.menuItem,
      initialQuantity: item.quantity,
      initialSelectedOptions: initialOptions.isNotEmpty ? initialOptions : null,
      initialNotes: item.notes,
    );
  }

  int get quantity => _quantity;
  String get notes => _notes;
  Map<String, Set<String>> get selectedOptionIds =>
      Map<String, Set<String>>.unmodifiable({
        for (final entry in _selectedOptionQuantities.entries)
          entry.key: Set<String>.unmodifiable(entry.value.keys),
      });
  Map<String, Map<String, int>> get selectedOptionQuantities =>
      Map<String, Map<String, int>>.unmodifiable({
        for (final entry in _selectedOptionQuantities.entries)
          entry.key: Map<String, int>.unmodifiable(entry.value),
      });

  void setNotes(String val) {
    _notes = val;
    notifyListeners();
  }

  void incrementQuantity() {
    _quantity++;
    notifyListeners();
  }

  void decrementQuantity() {
    if (_quantity > 1) {
      _quantity--;
      notifyListeners();
    }
  }

  void setQuantity(int qty) {
    if (qty >= 1) {
      _quantity = qty;
      notifyListeners();
    }
  }

  /// Automatically preselects first available option for required single-select groups (e.g. Level 0 pedas).
  void _initializeDefaults() {
    for (final group in menuItem.activeModifierGroups) {
      if (group.isRequired &&
          group.isSingleSelect &&
          group.options.isNotEmpty) {
        final firstAvailable = group.options.firstWhere(
          (opt) => opt.isAvailable,
          orElse: () => group.options.first,
        );
        if (firstAvailable.isAvailable) {
          _selectedOptionQuantities[group.id] = {firstAvailable.id: 1};
        }
      }
    }
  }

  bool isOptionSelected(String groupId, String optionId) {
    return optionQuantity(groupId, optionId) > 0;
  }

  int optionQuantity(String groupId, String optionId) =>
      _selectedOptionQuantities[groupId]?[optionId] ?? 0;

  /// Toggles or sets an option. Rejects unavailable options (Criteria #2).
  void toggleOption(MenuModifierGroup group, MenuOption option) {
    if (!option.isAvailable) {
      // Criteria #2: Item/option unavailable cannot be added
      return;
    }

    final current = _selectedOptionQuantities[group.id] ?? <String, int>{};

    if (group.isSingleSelect) {
      // Radio mode
      if (group.isRequired) {
        _selectedOptionQuantities[group.id] = {option.id: 1};
      } else {
        if (current.containsKey(option.id)) {
          _selectedOptionQuantities[group.id] = {};
        } else {
          _selectedOptionQuantities[group.id] = {option.id: 1};
        }
      }
    } else {
      // Checkbox / Multi-select mode
      final updated = Map<String, int>.from(current);
      if (updated.containsKey(option.id)) {
        updated.remove(option.id);
      } else {
        if (_selectionCount(updated) < group.maxSelect) {
          updated[option.id] = 1;
        }
      }
      _selectedOptionQuantities[group.id] = updated;
    }

    notifyListeners();
  }

  void incrementOption(MenuModifierGroup group, MenuOption option) {
    if (!option.isAvailable || group.isSingleSelect) return;
    final updated = Map<String, int>.from(
      _selectedOptionQuantities[group.id] ?? const {},
    );
    if (_selectionCount(updated) >= group.maxSelect) return;
    updated[option.id] = (updated[option.id] ?? 0) + 1;
    _selectedOptionQuantities[group.id] = updated;
    notifyListeners();
  }

  void decrementOption(MenuModifierGroup group, MenuOption option) {
    final updated = Map<String, int>.from(
      _selectedOptionQuantities[group.id] ?? const {},
    );
    final quantity = updated[option.id] ?? 0;
    if (quantity <= 1) {
      updated.remove(option.id);
    } else {
      updated[option.id] = quantity - 1;
    }
    _selectedOptionQuantities[group.id] = updated;
    notifyListeners();
  }

  int _selectionCount(Map<String, int> values) =>
      values.values.fold(0, (sum, quantity) => sum + quantity);

  int _groupSelectionCount(String groupId) =>
      _selectionCount(_selectedOptionQuantities[groupId] ?? const {});

  /// Validates a single modifier group.
  bool isGroupValid(MenuModifierGroup group) {
    final count = _groupSelectionCount(group.id);
    return count >= group.minSelect && count <= group.maxSelect;
  }

  /// Returns validation error messages for invalid groups (Criteria #3).
  Map<String, String> get validationErrors {
    final errors = <String, String>{};
    for (final group in menuItem.activeModifierGroups) {
      final count = _groupSelectionCount(group.id);
      if (count < group.minSelect) {
        if (group.minSelect == 1 && group.maxSelect == 1) {
          errors[group.id] = 'Wajib memilih 1 ${group.name}';
        } else {
          errors[group.id] = 'Pilih minimal ${group.minSelect} ${group.name}';
        }
      } else if (count > group.maxSelect) {
        errors[group.id] = 'Maksimal memilih ${group.maxSelect} ${group.name}';
      }
    }
    return errors;
  }

  /// True if all required modifier groups satisfy constraints (Criteria #3).
  bool get isValid => validationErrors.isEmpty;

  /// Calculates dynamic single-unit price with all selected modifiers.
  int get unitPrice {
    int total = menuItem.priceAmount;
    for (final group in menuItem.activeModifierGroups) {
      final quantities = _selectedOptionQuantities[group.id];
      if (quantities != null) {
        for (final option in group.options) {
          final quantity = quantities[option.id] ?? 0;
          if (quantity > 0) {
            total += option.priceDeltaAmount * quantity;
          }
        }
      }
    }
    return total;
  }

  /// Total price for configured quantity.
  int get totalPrice => unitPrice * _quantity;

  /// Human-readable summary of selected modifiers.
  List<String> get selectedOptionNames {
    final names = <String>[];
    for (final group in menuItem.activeModifierGroups) {
      final quantities = _selectedOptionQuantities[group.id];
      if (quantities != null) {
        for (final option in group.options) {
          final quantity = quantities[option.id] ?? 0;
          if (quantity > 0) {
            names.add(
              quantity == 1 ? option.name : '${option.name} ×$quantity',
            );
          }
        }
      }
    }
    return names;
  }

  String get formattedModifierSummary {
    final parts = selectedOptionNames;
    if (_notes.isNotEmpty) {
      parts.add('Catatan: $_notes');
    }
    return parts.join(', ');
  }
}
