import '../../menu/controllers/menu_availability_controller.dart';
import '../../menu/controllers/menu_controller.dart';
import '../local/menu_local_repository.dart';
import 'api_failure.dart';
import 'catalog_gateway.dart';

class CatalogRuntimeCoordinator {
  final CatalogRemoteGateway gateway;
  final MenuLocalRepository localRepository;
  final MenuController menuController;
  final MenuAvailabilityController managementController;

  bool _refreshing = false;
  bool _disposed = false;
  bool _hasCatalog = false;

  CatalogRuntimeCoordinator({
    required this.gateway,
    required this.localRepository,
    required this.menuController,
    required this.managementController,
  });

  Future<void> start() async {
    try {
      final cached = await localRepository.getCatalogWithFreshness();
      if (_disposed) return;
      if (cached.data.categories.isNotEmpty || cached.data.items.isNotEmpty) {
        _apply(cached.data, isOffline: true, cachedAt: cached.cachedAt);
      }
    } catch (_) {
      // A damaged/unavailable cache must not prevent recovery from Backend.
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    if (!_hasCatalog) menuController.setLoading();
    if (!_hasCatalog) {
      managementController.setLoading();
    }
    try {
      final remote = await gateway.fetchAdminCatalog();
      if (_disposed) return;
      final refreshedAt = DateTime.now();
      _apply(
        MenuCatalogSnapshot(categories: remote.categories, items: remote.menus),
        isOffline: false,
        cachedAt: refreshedAt,
      );
      try {
        await localRepository.saveCatalog(
          categories: remote.categories,
          items: remote.menus,
          cachedAt: refreshedAt,
        );
      } catch (_) {
        if (!_disposed) {
          managementController.setBanner(
            'Katalog terbaru aktif, tetapi cache offline belum dapat disimpan.',
            isError: true,
          );
        }
      }
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      _handleFailure(failure.presentationMessage);
    } catch (_) {
      if (_disposed) return;
      _handleFailure('Katalog terbaru belum dapat dimuat.');
    } finally {
      _refreshing = false;
    }
  }

  void _handleFailure(String message) {
    if (!_hasCatalog) {
      menuController.setError(message);
      managementController.setError(message);
      return;
    }
    _apply(
      MenuCatalogSnapshot(
        categories: menuController.categories,
        items: menuController.allMenus,
      ),
      isOffline: true,
      cachedAt: managementController.cachedAt,
    );
    managementController.setBanner(
      '$message Katalog cache tetap dapat dibaca.',
      isError: true,
    );
  }

  void _apply(
    MenuCatalogSnapshot snapshot, {
    required bool isOffline,
    DateTime? cachedAt,
  }) {
    _hasCatalog = true;
    menuController.setCatalog(
      snapshot.categories,
      snapshot.items,
      isOffline: isOffline,
      updatedAt: cachedAt,
    );
    managementController.setCatalog(
      snapshot.categories,
      snapshot.items,
      isOffline: isOffline,
      cachedAt: cachedAt,
    );
  }

  void dispose() => _disposed = true;
}
