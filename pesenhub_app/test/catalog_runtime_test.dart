import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesenhub_app/data/local/local_database.dart';
import 'package:pesenhub_app/data/local/menu_local_repository.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/api_failure.dart';
import 'package:pesenhub_app/data/remote/catalog_gateway.dart';
import 'package:pesenhub_app/data/remote/catalog_runtime_coordinator.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/menu/controllers/menu_availability_controller.dart';
import 'package:pesenhub_app/menu/controllers/menu_controller.dart' as mc;
import 'package:pesenhub_app/menu/menu_availability_view.dart';
import 'package:pesenhub_app/menu/models/menu_category.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:pesenhub_app/menu/models/menu_modifier_group.dart';
import 'package:pesenhub_app/menu/models/menu_option.dart';
import 'package:pesenhub_app/menu/models/menu_state.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _category = MenuCategory(id: 'category-1', name: 'Makanan', version: 2);
const _menu = MenuItem(
  id: 'menu-1',
  categoryId: 'category-1',
  sku: 'MAR-01',
  name: 'Martabak Telur',
  priceAmount: 20000,
  version: 3,
);

class _CatalogGateway implements CatalogRemoteGateway {
  final List<Object> outcomes;
  int calls = 0;

  _CatalogGateway(this.outcomes);

  @override
  Future<RemoteCatalog> fetchAdminCatalog() async {
    final value = outcomes[calls.clamp(0, outcomes.length - 1)];
    calls++;
    if (value is Exception) throw value;
    return value as RemoteCatalog;
  }

  @override
  Future<RemoteCatalog> fetchPublicCatalog() => fetchAdminCatalog();

  @override
  Future<MenuCategory> createCategory(MenuCategory category) async =>
      category.copyWith(id: 'created-category', version: 1);
  @override
  Future<MenuItem> createMenu(MenuItem menu) async =>
      menu.copyWith(id: 'created-menu', version: 1);
  @override
  Future<MenuCategory> updateCategory(MenuCategory category) async =>
      category.copyWith(version: category.version + 1);
  @override
  Future<MenuItem> updateMenu(MenuItem menu) async =>
      menu.copyWith(version: menu.version + 1);
  @override
  Future<MenuItem> updateMenuAvailability(
    String id,
    bool available,
    int expectedVersion,
  ) async =>
      _menu.copyWith(isAvailable: available, version: expectedVersion + 1);
}

class _FallbackCatalogGateway implements CatalogRemoteGateway {
  final Future<RemoteCatalog> Function() onFetchAdmin;
  final Future<RemoteCatalog> Function() onFetchPublic;

  _FallbackCatalogGateway({
    required this.onFetchAdmin,
    required this.onFetchPublic,
  });

  @override
  Future<RemoteCatalog> fetchAdminCatalog() => onFetchAdmin();

  @override
  Future<RemoteCatalog> fetchPublicCatalog() => onFetchPublic();

  @override
  Future<MenuCategory> createCategory(MenuCategory category) async => category;
  @override
  Future<MenuItem> createMenu(MenuItem menu) async => menu;
  @override
  Future<MenuCategory> updateCategory(MenuCategory category) async => category;
  @override
  Future<MenuItem> updateMenu(MenuItem menu) async => menu;
  @override
  Future<MenuItem> updateMenuAvailability(
    String id,
    bool available,
    int expectedVersion,
  ) async => _menu;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'cached catalog remains readable offline then refreshes both consumers',
    () async {
      final database = LocalDatabase(
        customPath: inMemoryDatabasePath,
        customFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final local = MenuLocalRepository(database);
      await local.saveCatalog(
        categories: const [_category],
        items: const [_menu],
      );
      final posCatalog = mc.MenuController();
      final management = MenuAvailabilityController();
      final gateway = _CatalogGateway([
        const ApiFailure(ApiFailureKind.network),
        const RemoteCatalog(
          categories: [_category],
          menus: [
            MenuItem(
              id: 'menu-1',
              categoryId: 'category-1',
              sku: 'MAR-01',
              name: 'Martabak Telur Baru',
              priceAmount: 23000,
              version: 4,
            ),
          ],
        ),
      ]);
      final coordinator = CatalogRuntimeCoordinator(
        gateway: gateway,
        localRepository: local,
        menuController: posCatalog,
        managementController: management,
      );

      await coordinator.start();
      expect(posCatalog.state.isOffline, isTrue);
      expect(management.state.isOffline, isTrue);
      expect(posCatalog.allMenus.single.name, 'Martabak Telur');

      await coordinator.refresh();
      expect(posCatalog.state.isOffline, isFalse);
      expect(management.state.isOffline, isFalse);
      expect(posCatalog.allMenus.single.priceAmount, 23000);
      expect(management.allMenus.single.version, 4);
    },
  );

  test(
    'fetchAdminCatalog 403 Forbidden falls back to fetchPublicCatalog seamlessly',
    () async {
      final database = LocalDatabase(
        customPath: inMemoryDatabasePath,
        customFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final local = MenuLocalRepository(database);
      final posCatalog = mc.MenuController();
      final management = MenuAvailabilityController();

      var adminCalled = false;
      var publicCalled = false;

      final gateway = _FallbackCatalogGateway(
        onFetchAdmin: () async {
          adminCalled = true;
          throw const ApiFailure(ApiFailureKind.forbidden, statusCode: 403);
        },
        onFetchPublic: () async {
          publicCalled = true;
          return const RemoteCatalog(
            categories: [_category],
            menus: [_menu],
          );
        },
      );

      final coordinator = CatalogRuntimeCoordinator(
        gateway: gateway,
        localRepository: local,
        menuController: posCatalog,
        managementController: management,
      );

      await coordinator.refresh();
      expect(adminCalled, isTrue);
      expect(publicCalled, isTrue);
      expect(posCatalog.state.status, MenuStatus.success);
      expect(management.state.status, MenuStatus.success);
      expect(posCatalog.allMenus.single.name, 'Martabak Telur');
    },
  );

  test(
    'offline management is read-only and conflict refreshes server state',
    () async {
      var availabilityCalls = 0;
      var refreshCalls = 0;
      final changes = <bool>[];
      var online = false;
      final controller = MenuAvailabilityController(
        initialCategories: const [_category],
        initialMenus: const [_menu],
        canMutate: () => online,
        availabilityUpdateFn: (_, _, _) async {
          availabilityCalls++;
          throw const ApiFailure(
            ApiFailureKind.conflict,
            requestId: 'request-conflict',
          );
        },
        onRefresh: () async => refreshCalls++,
        onAvailabilityChanged: (item) => changes.add(item.isAvailable),
      );
      expect(await controller.toggleAvailability('menu-1'), isFalse);
      expect(availabilityCalls, 0);
      expect(controller.bannerMessage, contains('offline'));

      online = true;
      expect(await controller.toggleAvailability('menu-1'), isFalse);
      expect(availabilityCalls, 1);
      expect(refreshCalls, 1);
      expect(changes, [false, true]);
      expect(controller.allMenus.single.isAvailable, isTrue);
      expect(controller.bannerMessage, contains('request-conflict'));
    },
  );

  test('CRUD callbacks publish a single shared catalog snapshot', () async {
    final gateway = _CatalogGateway(const []);
    var publications = 0;
    late List<MenuItem> publishedMenus;
    final controller = MenuAvailabilityController(
      initialCategories: const [_category],
      initialMenus: const [_menu],
      createCategoryFn: gateway.createCategory,
      updateCategoryFn: gateway.updateCategory,
      createMenuFn: gateway.createMenu,
      updateMenuFn: gateway.updateMenu,
      onCatalogChanged: (_, menus) {
        publications++;
        publishedMenus = menus;
      },
    );
    expect(
      await controller.saveCategory(
        const MenuCategory(id: '', name: 'Minuman'),
      ),
      isTrue,
    );
    expect(
      await controller.saveMenu(
        const MenuItem(
          id: '',
          categoryId: 'category-1',
          sku: 'TEH',
          name: 'Es Teh',
          priceAmount: 8000,
        ),
      ),
      isTrue,
    );
    expect(publications, 2);
    expect(publishedMenus.any((item) => item.id == 'created-menu'), isTrue);
  });

  test(
    'extra global diterapkan dan diwariskan berdasarkan jenis menu',
    () async {
      final menus = [
        _menu,
        _menu.copyWith(id: 'menu-2', sku: 'MAR-02'),
        _menu.copyWith(id: 'menu-3', sku: 'TB-01', productType: 'TERANG_BULAN'),
      ];
      MenuItem? createdDraft;
      final controller = MenuAvailabilityController(
        initialCategories: const [_category],
        initialMenus: menus,
        updateMenuFn: (value) async =>
            value.copyWith(version: value.version + 1),
        createMenuFn: (value) async {
          createdDraft = value;
          return value.copyWith(id: 'menu-new');
        },
      );
      const extra = MenuModifierGroup(
        id: '',
        code: 'extra_isian',
        name: 'Extra Isian',
        maxSelect: 20,
        options: [
          MenuOption(
            id: '',
            code: 'sapi',
            name: 'Sapi',
            priceDeltaAmount: 7000,
          ),
        ],
      );

      expect(
        await controller.saveGlobalExtras('MARTABAK_TELUR', extra),
        isTrue,
      );
      expect(
        controller.allMenus
            .where((menu) => menu.productType == 'MARTABAK_TELUR')
            .every((menu) => menu.modifierGroups.single.code == 'extra_isian'),
        isTrue,
      );
      expect(controller.allMenus.last.modifierGroups, isEmpty);

      expect(
        await controller.saveMenu(
          _menu.copyWith(id: '', sku: 'MAR-NEW', modifierGroups: const []),
        ),
        isTrue,
      );
      expect(createdDraft!.modifierGroups.single.code, 'extra_isian');
    },
  );

  test('API catalog requests carry session and optimistic version', () async {
    final requests = <http.Request>[];
    final client = PesenHubApiClient(
      config: ApiConfig(baseUri: Uri.parse('https://api.example.test/api/v1/')),
      accessToken: () async => 'session-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/admin/catalog')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'category-1',
                  'name': 'Makanan',
                  'sort_order': 0,
                  'is_active': true,
                  'version': 2,
                  'menus': [
                    {
                      'id': 'menu-1',
                      'category_id': 'category-1',
                      'sku': 'MAR-01',
                      'name': 'Martabak Telur',
                      'price_amount': 20000,
                      'is_available': true,
                      'version': 3,
                      'sort_order': 0,
                      'modifier_groups': [],
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'menu-1',
            'category_id': 'category-1',
            'sku': 'MAR-01',
            'name': 'Martabak Telur',
            'price_amount': 20000,
            'is_available': false,
            'version': 4,
            'sort_order': 0,
            'modifier_groups': [],
          }),
          200,
        );
      }),
    );

    expect((await client.fetchAdminCatalog()).menus, hasLength(1));
    await client.updateMenuAvailability('menu-1', false, 3);
    expect(
      requests.every(
        (request) => request.headers['Authorization'] == 'Bearer session-token',
      ),
      isTrue,
    );
    expect(jsonDecode(requests.last.body)['version'], 3);
  });

  testWidgets('management actions and menu editor fit mobile viewport', (
    tester,
  ) async {
    final controller = MenuAvailabilityController(
      initialCategories: const [_category],
      initialMenus: const [_menu],
      createCategoryFn: (value) async => value.copyWith(id: 'new-category'),
      createMenuFn: (value) async => value.copyWith(id: 'new-menu'),
      updateCategoryFn: (value) async => value,
      updateMenuFn: (value) async => value,
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: MenuAvailabilityView(controller: controller)),
      ),
    );
    await tester.tap(find.text('Tambah menu'));
    await tester.pumpAndSettle();
    expect(find.text('Tambah menu'), findsWidgets);
    expect(find.byKey(const Key('menu-name-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
