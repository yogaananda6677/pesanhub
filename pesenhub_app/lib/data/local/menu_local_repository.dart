import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../menu/models/menu_category.dart';
import '../../menu/models/menu_item.dart';
import '../../menu/models/menu_modifier_group.dart';
import '../../menu/models/menu_option.dart';
import 'local_database.dart';
import 'menu_image_cache_repository.dart';
import 'models/cached_result.dart';

/// Data class holding both categories and menu items snapshot.
class MenuCatalogSnapshot {
  final List<MenuCategory> categories;
  final List<MenuItem> items;

  const MenuCatalogSnapshot({required this.categories, required this.items});
}

/// MenuLocalRepository manages persistent SQLite storage and caching
/// for menu categories and menu catalog items.
/// Fulfills Issue #32 Acceptance Criteria #1 and #2.
class MenuLocalRepository {
  final LocalDatabase _localDb;

  static const String metadataKeyLastCached = 'catalog_last_cached_at';

  MenuLocalRepository(this._localDb);

  /// Saves the complete menu catalog into SQLite within an atomic transaction.
  Future<void> saveCatalog({
    required List<MenuCategory> categories,
    required List<MenuItem> items,
    DateTime? cachedAt,
  }) async {
    final db = await _localDb.database;
    final timestamp = (cachedAt ?? DateTime.now()).toIso8601String();

    await db.transaction((txn) async {
      // Clear existing catalog items
      await txn.delete('menus');
      await txn.delete('categories');

      // Insert categories
      for (final cat in categories) {
        await txn.insert('categories', {
          'id': cat.id,
          'name': cat.name,
          'sort_order': cat.sortOrder,
          'is_active': cat.isActive ? 1 : 0,
          'version': cat.version,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Insert menu items
      for (final item in items) {
        final modifierGroupsJson = jsonEncode(
          item.modifierGroups
              .map(
                (g) => {
                  'id': g.id,
                  'code': g.code,
                  'name': g.name,
                  'min_select': g.minSelect,
                  'max_select': g.maxSelect,
                  'sort_order': g.sortOrder,
                  'is_active': g.isActive,
                  'options': g.options
                      .map(
                        (o) => {
                          'id': o.id,
                          'code': o.code,
                          'name': o.name,
                          'price_delta_amount': o.priceDeltaAmount,
                          'is_available': o.isAvailable,
                          'sort_order': o.sortOrder,
                        },
                      )
                      .toList(),
                },
              )
              .toList(),
        );

        await txn.insert('menus', {
          'id': item.id,
          'category_id': item.categoryId,
          'sku': item.sku,
          'name': item.name,
          'description': item.description,
          'product_type': item.productType,
          'image_url': item.imageUrl,
          'price_amount': item.priceAmount,
          'hpp_amount': item.hppAmount,
          'channel_prices_json': jsonEncode(
            item.channelPrices.entries
                .map((entry) => {'channel': entry.key, 'amount': entry.value})
                .toList(),
          ),
          'is_available': item.isAvailable ? 1 : 0,
          'version': item.version,
          'sort_order': item.sortOrder,
          'is_drink': item.isDrink ? 1 : 0,
          'modifier_groups_json': modifierGroupsJson,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Record cache timestamp
      await txn.insert('sync_metadata', {
        'key': metadataKeyLastCached,
        'value': timestamp,
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Retrieves all cached categories sorted by sort_order ASC.
  Future<List<MenuCategory>> getCategories() async {
    final db = await _localDb.database;
    final rows = await db.query('categories', orderBy: 'sort_order ASC');

    return rows
        .map(
          (row) => MenuCategory(
            id: row['id'] as String,
            name: row['name'] as String,
            sortOrder: row['sort_order'] as int? ?? 0,
            isActive: (row['is_active'] as int? ?? 1) == 1,
            version: row['version'] as int? ?? 1,
          ),
        )
        .toList();
  }

  /// Retrieves cached menu items, optionally filtered by categoryId.
  Future<List<MenuItem>> getMenuItems({String? categoryId}) async {
    final db = await _localDb.database;
    final imageCache = await MenuImageCacheRepository(_localDb).getAll();
    final List<Map<String, dynamic>> rows;
    if (categoryId != null) {
      rows = await db.query(
        'menus',
        where: 'category_id = ?',
        whereArgs: [categoryId],
        orderBy: 'sort_order ASC',
      );
    } else {
      rows = await db.query('menus', orderBy: 'sort_order ASC');
    }

    return rows.map((row) {
      List<MenuModifierGroup> modifierGroups = [];
      final channelPrices = <String, int>{};
      final rawChannelPrices = row['channel_prices_json'] as String?;
      if (rawChannelPrices != null && rawChannelPrices.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawChannelPrices) as List<dynamic>;
          for (final entry in decoded) {
            if (entry is Map<String, dynamic> &&
                entry['channel'] is String &&
                entry['amount'] is int) {
              channelPrices[entry['channel'] as String] =
                  entry['amount'] as int;
            }
          }
        } catch (_) {
          channelPrices.clear();
        }
      }
      final rawGroups = row['modifier_groups_json'] as String?;
      if (rawGroups != null && rawGroups.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawGroups) as List<dynamic>;
          modifierGroups = decoded.map((g) {
            final rawOptions = g['options'] as List<dynamic>? ?? [];
            final options = rawOptions
                .map(
                  (o) => MenuOption(
                    id: o['id'] as String? ?? '',
                    code: o['code'] as String? ?? '',
                    name: o['name'] as String? ?? '',
                    priceDeltaAmount: o['price_delta_amount'] as int? ?? 0,
                    isAvailable: o['is_available'] as bool? ?? true,
                    sortOrder: o['sort_order'] as int? ?? 0,
                  ),
                )
                .toList();

            return MenuModifierGroup(
              id: g['id'] as String? ?? '',
              code: g['code'] as String? ?? '',
              name: g['name'] as String? ?? '',
              minSelect: g['min_select'] as int? ?? 0,
              maxSelect: g['max_select'] as int? ?? 1,
              sortOrder: g['sort_order'] as int? ?? 0,
              isActive:
                  g['isActive'] as bool? ?? g['is_active'] as bool? ?? true,
              options: options,
            );
          }).toList();
        } catch (_) {
          modifierGroups = [];
        }
      }

      final imageUrl = row['image_url'] as String?;
      final cachedImage = imageCache[row['id'] as String];
      return MenuItem(
        id: row['id'] as String,
        categoryId: row['category_id'] as String,
        sku: row['sku'] as String,
        name: row['name'] as String,
        description: row['description'] as String?,
        productType: row['product_type'] as String? ?? 'MARTABAK_TELUR',
        imageUrl: imageUrl,
        localImagePath: cachedImage?.sourceUrl == imageUrl
            ? cachedImage?.localPath
            : null,
        priceAmount: row['price_amount'] as int,
        hppAmount: row['hpp_amount'] as int?,
        channelPrices: channelPrices,
        isAvailable: (row['is_available'] as int) == 1,
        version: row['version'] as int? ?? 1,
        sortOrder: row['sort_order'] as int? ?? 0,
        isDrink: (row['is_drink'] as int? ?? 0) == 1,
        modifierGroups: modifierGroups,
      );
    }).toList();
  }

  /// Updates availability status and version for a specific menu item.
  Future<void> updateMenuAvailability(
    String id,
    bool isAvailable,
    int newVersion,
  ) async {
    final db = await _localDb.database;
    await db.update(
      'menus',
      {'is_available': isAvailable ? 1 : 0, 'version': newVersion},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Loads the entire catalog snapshot with cache timestamp and stale marker.
  Future<CachedResult<MenuCatalogSnapshot>> getCatalogWithFreshness({
    Duration staleThreshold = const Duration(minutes: 15),
  }) async {
    final categories = await getCategories();
    final items = await getMenuItems();

    final lastCachedStr = await _localDb.getMetadata(metadataKeyLastCached);
    DateTime? cachedAt;
    if (lastCachedStr != null) {
      cachedAt = DateTime.tryParse(lastCachedStr);
    }

    final isStale =
        cachedAt == null ||
        DateTime.now().difference(cachedAt) > staleThreshold;

    return CachedResult<MenuCatalogSnapshot>(
      data: MenuCatalogSnapshot(categories: categories, items: items),
      cachedAt: cachedAt,
      isStale: isStale,
    );
  }
}
