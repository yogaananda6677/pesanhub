import 'dart:async';
import 'package:flutter/material.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import '../models/menu_state.dart';

/// MenuController manages catalog menus, search with debounce, category filtering, and presentation states.
/// Fulfills Issue #27 Acceptance Criteria #1, #2, and #5.
class MenuController extends ChangeNotifier {
  List<MenuCategory> _categories = [];
  List<MenuItem> _menus = [];

  MenuState _state = const MenuState.loading();
  String _selectedCategoryId = 'ALL';
  String _searchQuery = '';
  Timer? _debounceTimer;

  MenuController({
    List<MenuCategory>? initialCategories,
    List<MenuItem>? initialMenus,
  }) {
    if (initialCategories != null && initialMenus != null) {
      setCatalog(initialCategories, initialMenus);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Getters
  MenuState get state => _state;
  String get selectedCategoryId => _selectedCategoryId;
  String get searchQuery => _searchQuery;
  List<MenuCategory> get categories => List.unmodifiable(_categories);
  List<MenuItem> get allMenus => List.unmodifiable(_menus);

  /// Total count of menu items in catalog.
  int get totalCount => _menus.length;

  /// Counts items belonging to a category (or all items if 'ALL').
  int countForCategory(String categoryId) {
    if (categoryId == 'ALL') return _menus.length;
    return _menus.where((m) => m.categoryId == categoryId).length;
  }

  /// Sets catalog items and categories.
  void setCatalog(
    List<MenuCategory> categories,
    List<MenuItem> menus, {
    bool isOffline = false,
  }) {
    _categories = categories;
    _menus = menus;

    if (_menus.isEmpty) {
      _state = MenuState.empty(isOffline: isOffline);
    } else {
      _state = MenuState.success(isOffline: isOffline);
    }
    notifyListeners();
  }

  /// Updates presentation error state.
  void setError(String message) {
    _state = MenuState.error(message);
    notifyListeners();
  }

  /// Updates presentation loading state.
  void setLoading() {
    _state = const MenuState.loading();
    notifyListeners();
  }

  /// Selects active category filter ('ALL' or category.id).
  void selectCategory(String categoryId) {
    if (_selectedCategoryId != categoryId) {
      _selectedCategoryId = categoryId;
      notifyListeners();
    }
  }

  /// Updates search query with a 250ms debounce (Criteria #1).
  void onSearchChanged(String query, {bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      _searchQuery = query;
      notifyListeners();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _searchQuery = query;
      notifyListeners();
    });
  }

  /// Updates availability of a menu item in-place (Criteria #2).
  void updateAvailability(String menuId, bool isAvailable) {
    final index = _menus.indexWhere((m) => m.id == menuId);
    if (index != -1) {
      _menus[index] = _menus[index].copyWith(isAvailable: isAvailable);
      notifyListeners();
    }
  }

  /// Returns filtered and searched items matching criteria.
  List<MenuItem> get filteredMenus {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = _menus.where((item) {
      // 1. Category Filter
      if (_selectedCategoryId != 'ALL' &&
          item.categoryId != _selectedCategoryId) {
        return false;
      }

      // 2. Search Query Filter
      if (query.isNotEmpty) {
        final matchesName = item.name.toLowerCase().contains(query);
        final matchesSku = item.sku.toLowerCase().contains(query);
        final matchesDesc =
            item.description?.toLowerCase().contains(query) ?? false;
        if (!matchesName && !matchesSku && !matchesDesc) {
          return false;
        }
      }

      return true;
    }).toList();

    filtered.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return filtered;
  }
}
