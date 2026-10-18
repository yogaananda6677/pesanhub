import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/remote/api_failure.dart';
import '../../core/utils/currency_formatter.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import '../models/menu_modifier_group.dart';
import '../models/menu_state.dart';

/// Callback signature for remote availability updates.
typedef AvailabilityUpdateFn =
    Future<MenuItem> Function(String menuId, bool isAvailable, int version);
typedef CategoryMutationFn = Future<MenuCategory> Function(MenuCategory value);
typedef MenuMutationFn = Future<MenuItem> Function(MenuItem value);
typedef CatalogChangedFn =
    void Function(List<MenuCategory> categories, List<MenuItem> menus);
typedef MenuImageUploadFn =
    Future<String> Function(String filename, List<int> bytes);
typedef BulkChannelPricesFn =
    Future<List<MenuItem>> Function(Map<String, double> rates);

/// MenuAvailabilityController manages menu availability status with role guards,
/// optimistic feedback, server rollback, version tracking, and synchronization.
/// Fulfills Issue #31 Acceptance Criteria #1, #2, #3, and #4.
class MenuAvailabilityController extends ChangeNotifier {
  List<MenuCategory> _categories = [];
  List<MenuItem> _menus = [];
  String role;

  final Set<String> _updatingMenuIds = <String>{};
  MenuState _state = const MenuState.loading();

  String _statusFilter = 'ALL'; // 'ALL', 'AVAILABLE', 'UNAVAILABLE'
  String _selectedCategoryId = 'ALL';
  String _searchQuery = '';
  Timer? _debounceTimer;

  String? _bannerMessage;
  bool _isBannerError = false;

  final AvailabilityUpdateFn? availabilityUpdateFn;
  final ValueChanged<MenuItem>? onAvailabilityChanged;
  final CategoryMutationFn? createCategoryFn;
  final CategoryMutationFn? updateCategoryFn;
  final MenuMutationFn? createMenuFn;
  final MenuMutationFn? updateMenuFn;
  final BulkChannelPricesFn? bulkChannelPricesFn;
  final Future<void> Function()? onRefresh;
  final bool Function()? canMutate;
  final CatalogChangedFn? onCatalogChanged;
  final MenuImageUploadFn? uploadMenuImageFn;
  bool _isSaving = false;
  DateTime? _cachedAt;

  MenuAvailabilityController({
    List<MenuCategory>? initialCategories,
    List<MenuItem>? initialMenus,
    this.role = 'STAFF',
    this.availabilityUpdateFn,
    this.onAvailabilityChanged,
    this.createCategoryFn,
    this.updateCategoryFn,
    this.createMenuFn,
    this.updateMenuFn,
    this.bulkChannelPricesFn,
    this.onRefresh,
    this.canMutate,
    this.onCatalogChanged,
    this.uploadMenuImageFn,
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
  bool get isStaff => role == 'ADMIN' || role == 'STAFF';
  MenuState get state => _state;
  String get statusFilter => _statusFilter;
  String get selectedCategoryId => _selectedCategoryId;
  String get searchQuery => _searchQuery;
  String? get bannerMessage => _bannerMessage;
  bool get isBannerError => _isBannerError;
  bool get isSaving => _isSaving;
  DateTime? get cachedAt => _cachedAt;
  bool get isOffline => _state.isOffline;
  bool get mutationEnabled =>
      isStaff && !isOffline && (canMutate?.call() ?? true);

  List<MenuCategory> get categories => List.unmodifiable(_categories);
  List<MenuItem> get allMenus => List.unmodifiable(_menus);
  Set<String> get updatingMenuIds => Set.unmodifiable(_updatingMenuIds);

  int get totalCount => _menus.length;
  int get availableCount => _menus.where((m) => m.isAvailable).length;
  int get unavailableCount => _menus.where((m) => !m.isAvailable).length;

  /// Updates the active role (e.g. for testing or profile switching).
  void setRole(String newRole) {
    if (role != newRole) {
      role = newRole;
      notifyListeners();
    }
  }

  /// Sets catalog items and categories.
  void setCatalog(
    List<MenuCategory> categories,
    List<MenuItem> menus, {
    bool isOffline = false,
    DateTime? cachedAt,
  }) {
    // CRUD needs controller-owned mutable lists; callers may provide const or
    // otherwise unmodifiable snapshots.
    _categories = List.from(categories);
    _menus = List.from(menus);
    _cachedAt = cachedAt ?? _cachedAt;

    if (_menus.isEmpty) {
      _state = MenuState.empty(isOffline: isOffline);
    } else {
      _state = MenuState.success(isOffline: isOffline);
    }
    notifyListeners();
  }

  /// Updates presentation state to loading.
  void setLoading() {
    _state = const MenuState.loading();
    notifyListeners();
  }

  /// Updates presentation state to error.
  void setError(String message) {
    _state = MenuState.error(message);
    notifyListeners();
  }

  /// Clears banner feedback message.
  void clearBanner() {
    _bannerMessage = null;
    _isBannerError = false;
    notifyListeners();
  }

  void connectivityChanged() => notifyListeners();

  void applyCachedImage(MenuItem menu) {
    final index = _menus.indexWhere((item) => item.id == menu.id);
    if (index == -1 || _menus[index].imageUrl != menu.imageUrl) return;
    _menus[index] = menu;
    notifyListeners();
  }

  Future<String> uploadMenuImage(String filename, List<int> bytes) async {
    if (!mutationEnabled || uploadMenuImageFn == null) {
      throw StateError('Upload gambar hanya tersedia untuk Admin online.');
    }
    return uploadMenuImageFn!(filename, bytes);
  }

  /// Sets banner message directly (e.g. for informational notices).
  void setBanner(String message, {bool isError = false}) {
    _bannerMessage = message;
    _isBannerError = isError;
    notifyListeners();
  }

  /// Selects category filter ('ALL' or category ID).
  void selectCategory(String categoryId) {
    if (_selectedCategoryId != categoryId) {
      _selectedCategoryId = categoryId;
      notifyListeners();
    }
  }

  /// Selects status filter ('ALL', 'AVAILABLE', 'UNAVAILABLE').
  void setStatusFilter(String filter) {
    if (_statusFilter != filter) {
      _statusFilter = filter;
      notifyListeners();
    }
  }

  /// Updates search query with 250ms debounce.
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

  /// Toggles availability of a menu item with role guard, optimistic feedback,
  /// version contract, and automatic rollback on failure.
  /// Fulfills Criteria #1, #2, #3, and #4.
  Future<bool> toggleAvailability(String menuId) async {
    // 1. Role Guard (Criteria #3)
    if (!isStaff) {
      _bannerMessage =
          'Akses ditolak: Hanya staf berwenang yang dapat mengubah ketersediaan menu.';
      _isBannerError = true;
      notifyListeners();
      return false;
    }
    if (!mutationEnabled) {
      _bannerMessage =
          'Perubahan menu dinonaktifkan saat offline. Hubungkan backend lalu coba lagi.';
      _isBannerError = true;
      notifyListeners();
      return false;
    }

    // 2. In-flight double action guard
    if (_updatingMenuIds.contains(menuId)) {
      return false;
    }

    final index = _menus.indexWhere((m) => m.id == menuId);
    if (index == -1) return false;

    final item = _menus[index];
    final previousAvailable = item.isAvailable;
    final previousVersion = item.version;
    final targetAvailable = !previousAvailable;

    // 3. Optimistic Update (Criteria #1 & #2)
    _updatingMenuIds.add(menuId);
    _menus[index] = item.copyWith(isAvailable: targetAvailable);
    _bannerMessage = null;
    notifyListeners();

    // Broadcast to synchronize with POS catalog (Criteria #4)
    onAvailabilityChanged?.call(_menus[index]);

    try {
      MenuItem updatedItem;
      if (availabilityUpdateFn != null) {
        // Version contract: send previousVersion to backend
        updatedItem = await availabilityUpdateFn!(
          menuId,
          targetAvailable,
          previousVersion,
        );
      } else {
        // Simulated local success with version increment
        updatedItem = item.copyWith(
          isAvailable: targetAvailable,
          version: previousVersion + 1,
        );
      }

      _menus[index] = updatedItem.modifierGroups.isEmpty
          ? updatedItem.copyWith(modifierGroups: item.modifierGroups)
          : updatedItem;
      _updatingMenuIds.remove(menuId);
      _bannerMessage =
          '${updatedItem.name} ditandai sebagai ${targetAvailable ? "Tersedia" : "Habis"}.';
      _isBannerError = false;
      notifyListeners();

      onAvailabilityChanged?.call(_menus[index]);
      _publishCatalog();
      return true;
    } catch (e) {
      // 4. Rollback on Failure (Criteria #2)
      _menus[index] = item.copyWith(
        isAvailable: previousAvailable,
        version: previousVersion,
      );
      _updatingMenuIds.remove(menuId);

      // Rollback synchronization on POS catalog
      onAvailabilityChanged?.call(_menus[index]);
      _publishCatalog();
      await _handleMutationFailure(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveCategory(MenuCategory draft) async {
    final create = draft.id.isEmpty;
    final operation = create ? createCategoryFn : updateCategoryFn;
    if (!_canStartMutation(operation != null)) return false;
    _isSaving = true;
    _bannerMessage = null;
    notifyListeners();
    try {
      final saved = await operation!(draft);
      final index = _categories.indexWhere((item) => item.id == saved.id);
      if (index == -1) {
        _categories.add(saved);
      } else {
        _categories[index] = saved;
      }
      _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _bannerMessage = create
          ? 'Kategori ${saved.name} berhasil ditambahkan.'
          : 'Kategori ${saved.name} berhasil diperbarui.';
      _isBannerError = false;
      _publishCatalog();
      return true;
    } catch (error) {
      await _handleMutationFailure(error);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> saveMenu(MenuItem draft) async {
    final create = draft.id.isEmpty;
    if (create && draft.modifierGroups.isEmpty) {
      final sharedExtra = globalExtraFor(draft.productType);
      if (sharedExtra != null) {
        draft = draft.copyWith(modifierGroups: [sharedExtra]);
      }
    }
    final operation = create ? createMenuFn : updateMenuFn;
    if (!_canStartMutation(operation != null)) return false;
    _isSaving = true;
    _bannerMessage = null;
    notifyListeners();
    try {
      final saved = await operation!(draft);
      final index = _menus.indexWhere((item) => item.id == saved.id);
      if (index == -1) {
        _menus.add(saved);
      } else {
        _menus[index] = saved;
      }
      _bannerMessage = create
          ? '${saved.name} tersimpan sebagai draft. Isi harga lalu aktifkan stok saat siap dijual.'
          : '${saved.name} berhasil diperbarui.';
      _isBannerError = false;
      _publishCatalog();
      return true;
    } catch (error) {
      await _handleMutationFailure(error);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  MenuModifierGroup? globalExtraFor(String productType) {
    for (final menu in _menus) {
      if (menu.productType != productType) continue;
      for (final group in menu.modifierGroups) {
        if (group.code == 'extra_isian') return group;
      }
    }
    return null;
  }

  Future<bool> saveGlobalExtras(
    String productType,
    MenuModifierGroup template,
  ) async {
    if (!_canStartMutation(updateMenuFn != null)) return false;
    _isSaving = true;
    _bannerMessage = null;
    notifyListeners();
    try {
      final targets = _menus
          .where((menu) => menu.productType == productType)
          .toList(growable: false);
      for (final menu in targets) {
        final groups = menu.modifierGroups
            .where((group) => group.code != 'extra_isian')
            .toList();
        groups.add(template);
        final saved = await updateMenuFn!(
          menu.copyWith(modifierGroups: groups),
        );
        final index = _menus.indexWhere((item) => item.id == saved.id);
        if (index != -1) _menus[index] = saved;
      }
      _bannerMessage =
          'Extra isian berhasil diterapkan ke ${targets.length} menu ${productType == "TERANG_BULAN" ? "Terang Bulan" : "Martabak Telur"}.';
      _isBannerError = false;
      _publishCatalog();
      return true;
    } catch (error) {
      await _handleMutationFailure(error);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<int> applyChannelPricesToAllMenus(Map<String, double> rates) async {
    if (!_canStartMutation(
      bulkChannelPricesFn != null || updateMenuFn != null,
    )) {
      return 0;
    }
    _isSaving = true;
    _bannerMessage = null;
    notifyListeners();
    try {
      if (bulkChannelPricesFn != null) {
        final updated = await bulkChannelPricesFn!(rates);
        for (final item in updated) {
          final index = _menus.indexWhere((m) => m.id == item.id);
          if (index != -1) {
            _menus[index] = _menus[index].copyWith(
              channelPrices: item.channelPrices,
              version: item.version,
            );
          }
        }
        _bannerMessage =
            'Harga kanal online berhasil diterapkan ke ${updated.length} menu.';
        _isBannerError = false;
        _publishCatalog();
        return updated.length;
      }

      int updatedCount = 0;
      final errors = <String>[];
      final targets = _menus
          .where((menu) => menu.priceAmount > 0)
          .toList(growable: false);
      const poolSize = 3;
      for (var i = 0; i < targets.length; i += poolSize) {
        final chunk = targets.skip(i).take(poolSize);
        await Future.wait(
          chunk.map((menu) async {
            try {
              final currentPrices = Map<String, int>.from(menu.channelPrices);
              currentPrices['OFFLINE'] = menu.priceAmount;
              for (final entry in rates.entries) {
                final ch = entry.key;
                final pct = entry.value;
                currentPrices[ch] = CurrencyFormatter.calculateOnlinePrice(
                  menu.priceAmount,
                  pct,
                );
              }
              for (final ch in const ['GOFOOD', 'GRABFOOD', 'SHOPEEFOOD']) {
                currentPrices.putIfAbsent(ch, () => menu.priceAmount);
              }
              final saved = await updateMenuFn!(
                menu.copyWith(
                  hppAmount: menu.hppAmount ?? 0,
                  channelPrices: currentPrices,
                ),
              );
              final index = _menus.indexWhere((item) => item.id == saved.id);
              if (index != -1) _menus[index] = saved;
              updatedCount++;
            } catch (e) {
              errors.add('${menu.name}: $e');
            }
          }),
        );
      }
      if (updatedCount > 0) {
        if (errors.isNotEmpty) {
          _bannerMessage =
              'Harga diterapkan ke $updatedCount menu (${errors.length} gagal).';
          _isBannerError = true;
        } else {
          _bannerMessage =
              'Harga kanal online berhasil diterapkan ke $updatedCount menu.';
          _isBannerError = false;
        }
        _publishCatalog();
        return updatedCount;
      } else if (errors.isNotEmpty) {
        throw Exception(errors.first);
      }
      return 0;
    } catch (error) {
      await _handleMutationFailure(error);
      return 0;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  bool _canStartMutation(bool configured) {
    if (_isSaving) return false;
    if (!mutationEnabled) {
      _bannerMessage =
          'Perubahan menu dinonaktifkan saat offline. Hubungkan backend lalu coba lagi.';
      _isBannerError = true;
      notifyListeners();
      return false;
    }
    if (!configured) {
      _bannerMessage = 'Layanan pengelolaan katalog belum dikonfigurasi.';
      _isBannerError = true;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> _handleMutationFailure(Object error) async {
    final failure = error is ApiFailure ? error : null;
    final request = failure?.requestId;
    final rawFallback = error.toString().replaceFirst('Exception: ', '');
    final fallback = rawFallback.length > 160
        ? rawFallback.substring(0, 160)
        : rawFallback;
    _bannerMessage = failure?.kind == ApiFailureKind.conflict
        ? 'Data katalog berubah di perangkat lain. Data terbaru dimuat ulang${request == null ? "." : " (ID: $request)."}'
        : '${failure?.presentationMessage ?? fallback}${request == null ? "" : " ID: $request"}';
    _isBannerError = true;
    if (failure?.kind == ApiFailureKind.conflict) await onRefresh?.call();
  }

  void _publishCatalog() {
    onCatalogChanged?.call(
      List.unmodifiable(_categories),
      List.unmodifiable(_menus),
    );
  }

  /// Returns filtered items matching status, category, and search criteria.
  List<MenuItem> get filteredMenus {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = _menus.where((item) {
      // 1. Status Filter
      if (_statusFilter == 'AVAILABLE' && !item.isAvailable) return false;
      if (_statusFilter == 'UNAVAILABLE' && item.isAvailable) return false;

      // 2. Category Filter
      if (_selectedCategoryId != 'ALL' &&
          item.categoryId != _selectedCategoryId) {
        return false;
      }

      // 3. Search Query Filter
      if (query.isNotEmpty) {
        final matchesName = item.name.toLowerCase().contains(query);
        final matchesSku = item.sku.toLowerCase().contains(query);
        final matchesDesc =
            item.description?.toLowerCase().contains(query) ?? false;
        final categoryName = _categories
            .where((c) => c.id == item.categoryId)
            .firstOrNull
            ?.name
            .toLowerCase();
        final matchesCategory = categoryName?.contains(query) ?? false;
        if (!matchesName && !matchesSku && !matchesDesc && !matchesCategory) {
          return false;
        }
      }

      return true;
    }).toList();

    filtered.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return filtered;
  }
}
