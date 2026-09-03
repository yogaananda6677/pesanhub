import 'package:flutter/foundation.dart';
import '../models/menu_item.dart';
import '../models/menu_modifier_group.dart';
import '../models/menu_option.dart';

/// ModifierSelectionState manages modifier selections, quantity, and price calculation for a menu item.
/// Fulfills Issue #27 Acceptance Criteria #2 and #3.
class ModifierSelectionState extends ChangeNotifier {
  final MenuItem menuItem;
  int _quantity = 1;
  final Map<String, Set<String>> _selectedOptionIds = {};
  String _notes = '';

  ModifierSelectionState({required this.menuItem, int initialQuantity = 1}) {
    _quantity = initialQuantity < 1 ? 1 : initialQuantity;
    _initializeDefaults();
  }

  int get quantity => _quantity;
  String get notes => _notes;
  Map<String, Set<String>> get selectedOptionIds =>
      Map.unmodifiable(_selectedOptionIds);

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
          _selectedOptionIds[group.id] = {firstAvailable.id};
        }
      }
    }
  }

  bool isOptionSelected(String groupId, String optionId) {
    return _selectedOptionIds[groupId]?.contains(optionId) ?? false;
  }

  /// Toggles or sets an option. Rejects unavailable options (Criteria #2).
  void toggleOption(MenuModifierGroup group, MenuOption option) {
    if (!option.isAvailable) {
      // Criteria #2: Item/option unavailable cannot be added
      return;
    }

    final currentSet = _selectedOptionIds[group.id] ?? <String>{};

    if (group.isSingleSelect) {
      // Radio mode
      if (group.isRequired) {
        _selectedOptionIds[group.id] = {option.id};
      } else {
        if (currentSet.contains(option.id)) {
          _selectedOptionIds[group.id] = {};
        } else {
          _selectedOptionIds[group.id] = {option.id};
        }
      }
    } else {
      // Checkbox / Multi-select mode
      final updatedSet = Set<String>.from(currentSet);
      if (updatedSet.contains(option.id)) {
        updatedSet.remove(option.id);
      } else {
        if (updatedSet.length < group.maxSelect) {
          updatedSet.add(option.id);
        }
      }
      _selectedOptionIds[group.id] = updatedSet;
    }

    notifyListeners();
  }

  /// Validates a single modifier group.
  bool isGroupValid(MenuModifierGroup group) {
    final count = _selectedOptionIds[group.id]?.length ?? 0;
    return count >= group.minSelect && count <= group.maxSelect;
  }

  /// Returns validation error messages for invalid groups (Criteria #3).
  Map<String, String> get validationErrors {
    final errors = <String, String>{};
    for (final group in menuItem.activeModifierGroups) {
      final count = _selectedOptionIds[group.id]?.length ?? 0;
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
      final selectedIds = _selectedOptionIds[group.id];
      if (selectedIds != null) {
        for (final option in group.options) {
          if (selectedIds.contains(option.id)) {
            total += option.priceDeltaAmount;
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
      final selectedIds = _selectedOptionIds[group.id];
      if (selectedIds != null) {
        for (final option in group.options) {
          if (selectedIds.contains(option.id)) {
            names.add(option.name);
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
