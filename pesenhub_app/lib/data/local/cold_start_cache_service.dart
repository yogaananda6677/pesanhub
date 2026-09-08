import '../../menu/models/sample_menu_data.dart';
import '../../queue/models/queue_order.dart';
import 'local_database.dart';
import 'menu_local_repository.dart';
import 'models/cached_result.dart';
import 'queue_local_repository.dart';

/// Aggregated cold start data containing cached catalog and queue snapshots.
class ColdStartSnapshot {
  final CachedResult<MenuCatalogSnapshot> catalog;
  final CachedResult<List<QueueOrder>> queue;
  final bool isOffline;

  const ColdStartSnapshot({
    required this.catalog,
    required this.queue,
    this.isOffline = false,
  });

  /// True if local SQLite cache contains any data.
  bool get hasCachedData =>
      catalog.data.items.isNotEmpty || queue.data.isNotEmpty;

  /// True if any cached snapshot is older than the stale threshold.
  bool get isStale => catalog.isStale || queue.isStale;

  /// Overall cache timestamp (earliest or latest).
  DateTime? get latestCachedAt {
    if (catalog.cachedAt == null) return queue.cachedAt;
    if (queue.cachedAt == null) return catalog.cachedAt;
    return catalog.cachedAt!.isAfter(queue.cachedAt!)
        ? catalog.cachedAt
        : queue.cachedAt;
  }
}

/// ColdStartCacheService hydrates initial POS/KDS state directly
/// from SQLite, enabling instant startup without network latency.
/// Fulfills Issue #32 Acceptance Criteria #2.
class ColdStartCacheService {
  final LocalDatabase localDb;
  final MenuLocalRepository menuRepo;
  final QueueLocalRepository queueRepo;

  ColdStartCacheService({
    required this.localDb,
    MenuLocalRepository? menuRepo,
    QueueLocalRepository? queueRepo,
  }) : menuRepo = menuRepo ?? MenuLocalRepository(localDb),
       queueRepo = queueRepo ?? QueueLocalRepository(localDb);

  /// Loads cached catalog and queue state with freshness evaluation.
  Future<ColdStartSnapshot> hydrate({
    Duration staleThreshold = const Duration(minutes: 15),
    bool isOffline = false,
  }) async {
    final catalogResult = await menuRepo.getCatalogWithFreshness(
      staleThreshold: staleThreshold,
    );

    final queueResult = await queueRepo.getOrdersWithFreshness(
      staleThreshold: staleThreshold,
    );

    return ColdStartSnapshot(
      catalog: catalogResult,
      queue: queueResult,
      isOffline: isOffline,
    );
  }

  /// Seeds default sample data into SQLite if the database is brand new and empty.
  Future<void> seedInitialSampleDataIfEmpty() async {
    final existingCategories = await menuRepo.getCategories();
    if (existingCategories.isNotEmpty) return;

    // Seed sample menu catalog
    await menuRepo.saveCatalog(
      categories: SampleMenuData.sampleCategories,
      items: SampleMenuData.sampleMenus,
      cachedAt: DateTime.now(),
    );
  }
}
