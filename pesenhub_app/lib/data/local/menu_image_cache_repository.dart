import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

class CachedMenuImage {
  final String menuId;
  final String sourceUrl;
  final String localPath;
  final int byteSize;
  final DateTime updatedAt;

  const CachedMenuImage({
    required this.menuId,
    required this.sourceUrl,
    required this.localPath,
    required this.byteSize,
    required this.updatedAt,
  });
}

/// Persistent index connecting a backend image URL to its device-local file.
class MenuImageCacheRepository {
  final LocalDatabase _localDb;

  MenuImageCacheRepository(this._localDb);

  Future<Map<String, CachedMenuImage>> getAll() async {
    final db = await _localDb.database;
    final rows = await db.query('menu_image_cache');
    return {
      for (final row in rows)
        row['menu_id'] as String: CachedMenuImage(
          menuId: row['menu_id'] as String,
          sourceUrl: row['source_url'] as String,
          localPath: row['local_path'] as String,
          byteSize: row['byte_size'] as int,
          updatedAt: DateTime.parse(row['updated_at'] as String),
        ),
    };
  }

  Future<void> put(CachedMenuImage image) async {
    final db = await _localDb.database;
    await db.insert('menu_image_cache', {
      'menu_id': image.menuId,
      'source_url': image.sourceUrl,
      'local_path': image.localPath,
      'byte_size': image.byteSize,
      'updated_at': image.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String menuId) async {
    final db = await _localDb.database;
    await db.delete(
      'menu_image_cache',
      where: 'menu_id = ?',
      whereArgs: [menuId],
    );
  }
}
