import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/cart/controllers/cart_controller.dart';
import 'package:pesenhub_app/menu/controllers/menu_availability_controller.dart';
import 'package:pesenhub_app/menu/controllers/menu_controller.dart' as mc;
import 'package:pesenhub_app/menu/menu_availability_view.dart';
import 'package:pesenhub_app/menu/models/menu_category.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:pesenhub_app/menu/widgets/menu_availability_card.dart';
import 'package:pesenhub_app/pos/pos_view.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';

void main() {
  const testCategories = [
    MenuCategory(id: 'cat-food', name: 'Makanan', sortOrder: 0),
    MenuCategory(id: 'cat-drink', name: 'Minuman', sortOrder: 1),
  ];

  List<MenuItem> createTestMenus() => [
    const MenuItem(
      id: 'menu-1',
      categoryId: 'cat-food',
      sku: 'NGS-01',
      name: 'Nasi Goreng Spesial',
      description: 'Nasi goreng lezat dengan telur dan ayam suwir',
      priceAmount: 25000,
      isAvailable: true,
      version: 1,
      sortOrder: 0,
    ),
    const MenuItem(
      id: 'menu-2',
      categoryId: 'cat-drink',
      sku: 'ETM-01',
      name: 'Es Teh Manis',
      description: 'Teh melati manis segar dingin',
      priceAmount: 5000,
      isAvailable: true,
      version: 1,
      sortOrder: 1,
      isDrink: true,
    ),
    const MenuItem(
      id: 'menu-3',
      categoryId: 'cat-food',
      sku: 'MGS-01',
      name: 'Mie Goreng Seafood',
      description: 'Mie goreng dengan udang dan cumi',
      priceAmount: 32000,
      isAvailable: false, // Initial Out of Stock
      version: 1,
      sortOrder: 2,
    ),
  ];

  group('Issue #31 — Menu Availability Management Tests', () {
    test(
      'Criteria #1: Successful toggle updates version and notifies listeners/sync',
      () async {
        MenuItem? notifiedItem;
        final controller = MenuAvailabilityController(
          initialCategories: testCategories,
          initialMenus: createTestMenus(),
          role: 'STAFF',
          availabilityUpdateFn: (menuId, isAvailable, version) async {
            // Simulated backend response with incremented version
            return createTestMenus()
                .firstWhere((m) => m.id == menuId)
                .copyWith(isAvailable: isAvailable, version: version + 1);
          },
          onAvailabilityChanged: (item) {
            notifiedItem = item;
          },
        );

        // Initially menu-1 is available
        expect(
          controller.allMenus.firstWhere((m) => m.id == 'menu-1').isAvailable,
          isTrue,
        );
        expect(
          controller.allMenus.firstWhere((m) => m.id == 'menu-1').version,
          equals(1),
        );

        // Toggle to unavailable
        final success = await controller.toggleAvailability('menu-1');
        expect(success, isTrue);

        final updated = controller.allMenus.firstWhere((m) => m.id == 'menu-1');
        expect(updated.isAvailable, isFalse);
        expect(updated.version, equals(2)); // Version incremented

        expect(notifiedItem, isNotNull);
        expect(notifiedItem!.id, equals('menu-1'));
        expect(notifiedItem!.isAvailable, isFalse);
        expect(notifiedItem!.version, equals(2));
        expect(controller.bannerMessage, contains('ditandai sebagai Habis'));
        expect(controller.isBannerError, isFalse);
      },
    );

    test(
      'Criteria #2: Mutation failure triggers rollback to server state and actionable feedback',
      () async {
        MenuItem? lastSyncItem;
        final controller = MenuAvailabilityController(
          initialCategories: testCategories,
          initialMenus: createTestMenus(),
          role: 'STAFF',
          availabilityUpdateFn: (menuId, isAvailable, version) async {
            // Simulate version conflict from server
            throw Exception(
              'VERSION_CONFLICT: Menu telah diperbarui oleh perangkat lain.',
            );
          },
          onAvailabilityChanged: (item) {
            lastSyncItem = item;
          },
        );

        // Initially menu-1 is available with version 1
        expect(
          controller.allMenus.firstWhere((m) => m.id == 'menu-1').isAvailable,
          isTrue,
        );
        expect(
          controller.allMenus.firstWhere((m) => m.id == 'menu-1').version,
          equals(1),
        );

        // Attempt toggle
        final success = await controller.toggleAvailability('menu-1');
        expect(success, isFalse);

        // Must rollback to original available = true and version = 1
        final rolledBack = controller.allMenus.firstWhere(
          (m) => m.id == 'menu-1',
        );
        expect(rolledBack.isAvailable, isTrue);
        expect(rolledBack.version, equals(1));

        expect(lastSyncItem, isNotNull);
        expect(lastSyncItem!.isAvailable, isTrue);

        // Actionable error banner
        expect(controller.bannerMessage, contains('VERSION_CONFLICT'));
        expect(controller.isBannerError, isTrue);
      },
    );

    test(
      'Criteria #3: Unauthorized roles (KDS, CUSTOMER) cannot mutate availability',
      () async {
        final controller = MenuAvailabilityController(
          initialCategories: testCategories,
          initialMenus: createTestMenus(),
          role: 'KDS', // Not STAFF
        );

        expect(controller.isStaff, isFalse);

        // Attempt toggle as KDS
        final success = await controller.toggleAvailability('menu-1');
        expect(success, isFalse);

        // Menu status is unchanged
        expect(
          controller.allMenus.firstWhere((m) => m.id == 'menu-1').isAvailable,
          isTrue,
        );
        expect(controller.bannerMessage, contains('Akses ditolak'));
        expect(controller.isBannerError, isTrue);
      },
    );

    testWidgets(
      'Criteria #3 UI: MenuAvailabilityCard disables toggle switch when not staff',
      (tester) async {
        final item = createTestMenus().first;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: MenuAvailabilityCard(
                item: item,
                categoryName: 'Makanan',
                isStaff: false, // Unauthorized
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch is disabled (onChanged is null)
        final switchWidget = tester.widget<Switch>(find.byType(Switch));
        expect(switchWidget.onChanged, isNull);

        // Role restriction notice is visible
        expect(
          find.text('Hanya staf kasir yang dapat mengubah ketersediaan'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criteria #4: Setting item unavailable immediately prevents it from being ordered in POS',
      (tester) async {
        final posMenuController = mc.MenuController(
          initialCategories: testCategories,
          initialMenus: createTestMenus(),
        );
        final posCartController = CartController();

        final availabilityController = MenuAvailabilityController(
          initialCategories: testCategories,
          initialMenus: createTestMenus(),
          role: 'STAFF',
          onAvailabilityChanged: (updatedItem) {
            // Synchronize with POS Menu Controller
            posMenuController.updateAvailability(
              updatedItem.id,
              updatedItem.isAvailable,
            );
          },
        );

        // Mount PosView
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: PosView(
                menuController: posMenuController,
                cartController: posCartController,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initially menu-1 (Nasi Goreng Spesial) is available and can be tapped/added
        expect(posMenuController.allMenus.first.isAvailable, isTrue);
        expect(find.text('Nasi Goreng Spesial'), findsOneWidget);

        // 2. Mark menu-1 as unavailable via availabilityController
        await availabilityController.toggleAvailability('menu-1');
        await tester.pumpAndSettle();

        // 3. In POS view, Nasi Goreng Spesial now shows "Habis" badge
        expect(find.text('Habis'), findsNWidgets(2)); // menu-3 and now menu-1
        expect(posMenuController.allMenus.first.isAvailable, isFalse);

        // 4. Cart remains empty (cannot add unavailable item)
        expect(posCartController.totalItemCount, equals(0));
      },
    );

    testWidgets(
      'Criteria #5: Responsive layout on mobile and tablet with loading, empty, error, and filter states',
      (tester) async {
        final controller = MenuAvailabilityController(
          initialCategories: testCategories,
          initialMenus: createTestMenus(),
          role: 'STAFF',
        );

        // 1. Mobile Viewport (< 600dp)
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: MenuAvailabilityView(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(MenuAvailabilityCard), findsNWidgets(3));
        expect(find.text('Pengelolaan Menu (Staf Aktif)'), findsOneWidget);

        // 2. Tablet Viewport (>= 600dp)
        tester.view.physicalSize = const Size(900, 1200);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(MenuAvailabilityCard), findsNWidgets(3));

        // 3. Status Filters: Tap "Habis"
        expect(find.text('Habis (1)'), findsOneWidget);
        await tester.tap(find.text('Habis (1)'));
        await tester.pumpAndSettle();

        // Now only 1 card (Mie Goreng Seafood) is visible
        expect(find.byType(MenuAvailabilityCard), findsOneWidget);
        expect(find.text('Mie Goreng Seafood'), findsOneWidget);

        // 4. Empty State: Search for non-existent item
        controller.setStatusFilter('ALL');
        controller.onSearchChanged('Pizza Rendang', immediate: true);
        await tester.pumpAndSettle();

        expect(find.byType(AppEmptyState), findsOneWidget);
        expect(find.text('Tidak Ada Menu Ditemukan'), findsOneWidget);

        // 5. Loading State
        controller.onSearchChanged('', immediate: true);
        controller.setLoading();
        await tester.pump();

        expect(find.byType(AppLoadingState), findsOneWidget);
        expect(find.text('Memuat data ketersediaan menu...'), findsOneWidget);

        // 6. Error State
        controller.setError('Koneksi katalog backend terputus');
        await tester.pumpAndSettle();

        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.text('Koneksi katalog backend terputus'), findsOneWidget);
      },
    );
  });
}
