import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../menu/models/menu_item.dart';
import '../local/menu_image_cache_repository.dart';

typedef MenuImageCached = FutureOr<void> Function(MenuItem menu);
typedef CacheDirectoryProvider = Future<Directory> Function();

/// Downloads menu images one-by-one and only when the backend URL changes.
/// The backend creates a new immutable URL for every upload, so URL equality is
/// the image version check and no image bytes are fetched unnecessarily.
class MenuImageCacheWorker {
  static const int maxImageBytes = 5 * 1024 * 1024;

  final MenuImageCacheRepository repository;
  final http.Client _client;
  final bool _ownsClient;
  final CacheDirectoryProvider _cacheDirectoryProvider;

  bool _running = false;
  bool _disposed = false;

  MenuImageCacheWorker({
    required this.repository,
    http.Client? client,
    CacheDirectoryProvider? cacheDirectoryProvider,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _cacheDirectoryProvider =
           cacheDirectoryProvider ?? _defaultCacheDirectory;

  static Future<Directory> _defaultCacheDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'menu_images'));
  }

  /// Adds valid local paths to a fresh backend catalog without network I/O.
  Future<List<MenuItem>> resolveCached(List<MenuItem> menus) async {
    final indexed = await repository.getAll();
    final resolved = <MenuItem>[];
    for (final menu in menus) {
      final cached = indexed[menu.id];
      if (cached != null &&
          cached.sourceUrl == menu.imageUrl &&
          await File(cached.localPath).exists()) {
        resolved.add(menu.copyWith(localImagePath: cached.localPath));
      } else {
        resolved.add(menu);
      }
    }
    return resolved;
  }

  /// Reconciles the whole catalog sequentially to avoid a burst of downloads.
  Future<void> synchronize(
    List<MenuItem> menus, {
    MenuImageCached? onImageCached,
  }) async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final directory = await _cacheDirectoryProvider();
      await directory.create(recursive: true);
      final indexed = await repository.getAll();
      final activeMenuIds = menus.map((menu) => menu.id).toSet();

      for (final stale in indexed.values.where(
        (entry) => !activeMenuIds.contains(entry.menuId),
      )) {
        await _removeCached(stale);
      }

      for (final menu in menus) {
        if (_disposed) return;
        final url = menu.imageUrl?.trim();
        final current = indexed[menu.id];
        if (url == null || url.isEmpty) {
          if (current != null) await _removeCached(current);
          continue;
        }
        if (current != null &&
            current.sourceUrl == url &&
            await File(current.localPath).exists()) {
          continue;
        }

        final downloaded = await _download(menu, url, directory);
        if (downloaded == null || _disposed) continue;
        await repository.put(downloaded);
        if (current != null && current.localPath != downloaded.localPath) {
          await _deleteFile(current.localPath);
        }
        await onImageCached?.call(
          menu.copyWith(localImagePath: downloaded.localPath),
        );
      }
    } catch (_) {
      // Cache storage is an optimization; failures must not affect catalog use.
    } finally {
      _running = false;
    }
  }

  Future<CachedMenuImage?> _download(
    MenuItem menu,
    String sourceUrl,
    Directory directory,
  ) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      final bytes = response.bodyBytes;
      if (response.statusCode != HttpStatus.ok ||
          bytes.isEmpty ||
          bytes.length > maxImageBytes ||
          !_isSupportedImage(bytes)) {
        return null;
      }
      final sourceName = uri.pathSegments.isEmpty
          ? 'image.jpg'
          : uri.pathSegments.last;
      final extension = p.extension(sourceName).toLowerCase();
      final safeExtension =
          {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
          ? extension
          : '.jpg';
      final safeMenuId = menu.id.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
      final versionName = p
          .basenameWithoutExtension(sourceName)
          .replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
      final target = File(
        p.join(directory.path, '${safeMenuId}_$versionName$safeExtension'),
      );
      final temporary = File('${target.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      return CachedMenuImage(
        menuId: menu.id,
        sourceUrl: sourceUrl,
        localPath: target.path,
        byteSize: bytes.length,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      // A failed image must never block catalog/order synchronization. The next
      // catalog polling cycle retries it.
      return null;
    }
  }

  bool _isSupportedImage(List<int> bytes) {
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final png =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final webp =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return jpeg || png || webp;
  }

  Future<void> _removeCached(CachedMenuImage image) async {
    await repository.remove(image.menuId);
    await _deleteFile(image.localPath);
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Orphan cleanup can be retried without impacting the active catalog.
    }
  }

  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
  }
}
