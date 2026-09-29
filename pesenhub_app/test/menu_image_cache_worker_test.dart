import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/data/local/menu_image_cache_repository.dart';
import 'package:pesenhub_app/data/local/menu_local_repository.dart';
import 'package:pesenhub_app/data/sync/menu_image_cache_worker.dart';
import 'package:pesenhub_app/menu/models/menu_category.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('worker hanya mengunduh URL baru dan mengganti file lama', () async {
    final database = LocalDatabase(
      customPath: inMemoryDatabasePath,
      customFactory: databaseFactoryFfi,
    );
    final directory = await Directory.systemTemp.createTemp(
      'pesenhub-menu-image-test-',
    );
    addTearDown(() async {
      await database.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response.bytes(
        <int>[0xff, 0xd8, 0xff, ...List<int>.filled(32, requests)],
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    });
    final repository = MenuImageCacheRepository(database);
    final worker = MenuImageCacheWorker(
      repository: repository,
      client: client,
      cacheDirectoryProvider: () async => directory,
    );
    addTearDown(worker.dispose);

    const first = MenuItem(
      id: 'menu-1',
      categoryId: 'cat-1',
      sku: 'MAR-1',
      name: 'Martabak',
      imageUrl: 'http://api.test/uploads/image-v1.jpg',
      priceAmount: 20000,
    );
    MenuItem? downloaded;
    await worker.synchronize(const [
      first,
    ], onImageCached: (menu) => downloaded = menu);
    final firstPath = downloaded!.localImagePath!;
    expect(requests, 1);
    expect(await File(firstPath).exists(), isTrue);

    await worker.synchronize(const [first]);
    expect(requests, 1, reason: 'URL yang sama tidak boleh diunduh ulang');
    final resolved = await worker.resolveCached(const [first]);
    expect(resolved.single.localImagePath, firstPath);
    final catalogRepository = MenuLocalRepository(database);
    await catalogRepository.saveCatalog(
      categories: const [MenuCategory(id: 'cat-1', name: 'Martabak')],
      items: const [first],
    );
    expect(
      (await catalogRepository.getMenuItems()).single.localImagePath,
      firstPath,
      reason: 'cold start harus langsung memakai file lokal',
    );

    final replacement = first.copyWith(
      imageUrl: 'http://api.test/uploads/image-v2.jpg',
    );
    await worker.synchronize([replacement]);
    final cached = (await repository.getAll())['menu-1']!;
    expect(requests, 2);
    expect(cached.sourceUrl, replacement.imageUrl);
    expect(cached.localPath, isNot(firstPath));
    expect(await File(cached.localPath).exists(), isTrue);
    expect(await File(firstPath).exists(), isFalse);
  });
}
