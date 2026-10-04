import 'dart:async';

import '../../menu/controllers/menu_availability_controller.dart';
import '../../menu/controllers/menu_controller.dart';
import '../../menu/models/menu_item.dart';
import '../local/menu_local_repository.dart';
import '../sync/menu_image_cache_worker.dart';
import 'api_failure.dart';
import 'catalog_gateway.dart';

class CatalogRuntimeCoordinator {
  final CatalogRemoteGateway gateway;
  final MenuLocalRepository localRepository;
  final MenuController menuController;
  final MenuAvailabilityController managementController;
  final MenuImageCacheWorker? imageCacheWorker;
  final Duration pollingInterval;

  bool _refreshing = false;
  bool _pendingRefresh = false;
  bool _disposed = false;
  bool _hasCatalog = false;
  Timer? _pollingTimer;

  CatalogRuntimeCoordinator({
    required this.gateway,
    required this.localRepository,
    required this.menuController,
    required this.managementController,
    this.imageCacheWorker,
    this.pollingInterval = const Duration(minutes: 1),
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
    if (!_disposed && pollingInterval > Duration.zero) {
      _pollingTimer = Timer.periodic(
        pollingInterval,
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_refreshing) {
      _pendingRefresh = true;
      return;
    }
    _refreshing = true;
    _pendingRefresh = false;
    if (!_hasCatalog) menuController.setLoading();
    if (!_hasCatalog) {
      managementController.setLoading();
    }
    try {
      RemoteCatalog remote;
      try {
        remote = await gateway.fetchAdminCatalog();
      } on ApiFailure catch (failure) {
        if (failure.kind == ApiFailureKind.unauthenticated ||
            failure.kind == ApiFailureKind.forbidden) {
          remote = await gateway.fetchPublicCatalog();
        } else {
          rethrow;
        }
      } catch (_) {
        rethrow;
      }
      if (_disposed) return;
      final refreshedAt = DateTime.now();
      var resolvedMenus = remote.menus;
      try {
        if (imageCacheWorker != null) {
          resolvedMenus = await imageCacheWorker!.resolveCached(remote.menus);
        }
      } catch (_) {
        // Catalog data remains usable even if the optional image cache fails.
      }
      if (_disposed) return;
      _apply(
        MenuCatalogSnapshot(
          categories: remote.categories,
          items: resolvedMenus,
        ),
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
      unawaited(
        imageCacheWorker?.synchronize(
              remote.menus,
              onImageCached: _applyDownloadedImage,
            ) ??
            Future<void>.value(),
      );
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      _handleFailure(failure.presentationMessage);
    } catch (_) {
      if (_disposed) return;
      _handleFailure('Katalog terbaru belum dapat dimuat.');
    } finally {
      _refreshing = false;
      if (_pendingRefresh && !_disposed) {
        _pendingRefresh = false;
        unawaited(refresh());
      }
    }
  }

  void _applyDownloadedImage(MenuItem downloaded) {
    if (_disposed) return;
    final current = menuController.allMenus
        .where((menu) => menu.id == downloaded.id)
        .firstOrNull;
    if (current == null || current.imageUrl != downloaded.imageUrl) return;
    final updated = current.copyWith(localImagePath: downloaded.localImagePath);
    menuController.upsertMenu(updated);
    managementController.applyCachedImage(updated);
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

  void dispose() {
    _disposed = true;
    _pollingTimer?.cancel();
    imageCacheWorker?.dispose();
  }
}
