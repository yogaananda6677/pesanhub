import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/menu/controllers/menu_controller.dart' as mc;
import 'package:pesenhub_app/menu/controllers/modifier_selection_state.dart';
import 'package:pesenhub_app/menu/menu_catalog_view.dart';
import 'fixtures/sample_menu_data.dart';
import 'package:pesenhub_app/menu/widgets/menu_item_card.dart';
import 'package:pesenhub_app/menu/widgets/modifier_config_dialog.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';

void main() {
  Widget buildMenuTestApp(mc.MenuController controller) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: MenuCatalogView(controller: controller)),
    );
  }

  group('Issue #27: Menu Search, Category Filter, and Modifiers Tests', () {
    test('extra yang sama dapat dipilih berulang seperti sapi x3', () {
      final menu = SampleMenuData.sampleMenus.firstWhere(
        (item) => item.id == 'm-nasgor-spesial',
      );
      final group = SampleMenuData.toppingGroup;
      final sapi = group.options.firstWhere((option) => option.code == 'sosis');
      final state = ModifierSelectionState(menuItem: menu);

      state.incrementOption(group, sapi);
      state.incrementOption(group, sapi);
      state.incrementOption(group, sapi);
      state.incrementOption(group, sapi);

      expect(state.optionQuantity(group.id, sapi.id), 3);
      expect(state.unitPrice, 34000);
      expect(state.formattedModifierSummary, contains('×3'));
    });

    testWidgets(
      'Criteria #1: Search with debounce and category filter work accurately',
      (tester) async {
        final controller = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );

        await tester.pumpWidget(buildMenuTestApp(controller));
        await tester.pumpAndSettle();

        // All menus displayed initially
        expect(find.text('Martabak Telur Spesial'), findsOneWidget);
        expect(find.text('Es Teh Manis'), findsOneWidget);

        // Filter by category 'Minuman'
        await tester.tap(find.text('Minuman (2)'));
        await tester.pumpAndSettle();

        expect(find.text('Es Teh Manis'), findsOneWidget);
        expect(find.text('Es Jeruk Peras'), findsOneWidget);
        expect(find.text('Martabak Telur Spesial'), findsNothing);

        // Return to 'Semua'
        await tester.tap(find.text('Semua (13)'));
        await tester.pumpAndSettle();

        // Search by query 'Bebek'
        controller.onSearchChanged('Bebek', immediate: true);
        await tester.pumpAndSettle();

        expect(find.text('Martabak Telur Bebek'), findsOneWidget);
        expect(find.text('Martabak Telur Spesial'), findsNothing);
        expect(find.text('Es Teh Manis'), findsNothing);
      },
    );

    testWidgets(
      'Criteria #2: Unavailable menu item cannot be added and shows Habis badge',
      (tester) async {
        final controller = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );

        await tester.pumpWidget(buildMenuTestApp(controller));
        await tester.pumpAndSettle();

        // Find the unavailable item 'Terang Bulan Toblerone Keju'
        expect(find.text('Terang Bulan Toblerone Keju'), findsOneWidget);
        expect(find.text('Habis'), findsOneWidget);

        // Verify the button for unavailable item cannot be pressed
        final unavailableCard = find.widgetWithText(
          MenuItemCard,
          'Terang Bulan Toblerone Keju',
        );
        expect(unavailableCard, findsOneWidget);

        // Tapping on unavailable item does NOT open dialog
        await tester.tap(unavailableCard);
        await tester.pumpAndSettle();

        expect(find.byType(ModifierConfigDialog), findsNothing);
      },
    );

    testWidgets(
      'Criteria #3: Required modifier, max topping limits, and dynamic price calculation',
      (tester) async {
        final nasgor = SampleMenuData.sampleMenus.firstWhere(
          (m) => m.id == 'm-nasgor-spesial',
        );
        final state = ModifierSelectionState(menuItem: nasgor);

        // Initial state: Level pedas defaults to first option (Level 0)
        expect(state.quantity, equals(1));
        expect(state.unitPrice, equals(25000));
        expect(state.totalPrice, equals(25000));
        expect(state.isValid, isTrue);

        // Select topping 'Telur Ceplok' (+Rp 4.000)
        final toppingGroup = SampleMenuData.toppingGroup;
        final optCeplok = toppingGroup.options.firstWhere(
          (o) => o.code == 'ceplok',
        );
        state.toggleOption(toppingGroup, optCeplok);

        expect(state.unitPrice, equals(29000));
        expect(state.totalPrice, equals(29000));

        // Add topping 'Sosis Sapi' (+Rp 3.000)
        final optSosis = toppingGroup.options.firstWhere(
          (o) => o.code == 'sosis',
        );
        state.toggleOption(toppingGroup, optSosis);
        expect(state.unitPrice, equals(32000));

        // Add topping 'Bakso Sapi' (+Rp 3.000) -> 3 toppings (at maxSelect 3)
        final optBakso = toppingGroup.options.firstWhere(
          (o) => o.code == 'bakso',
        );
        state.toggleOption(toppingGroup, optBakso);
        expect(state.unitPrice, equals(35000));

        // Attempting to add 4th topping should be rejected by maxSelect constraint
        final optDadar = toppingGroup.options.firstWhere(
          (o) => o.code == 'dadar',
        );
        state.toggleOption(toppingGroup, optDadar);
        expect(state.selectedOptionIds[toppingGroup.id]?.length, equals(3));
        expect(state.unitPrice, equals(35000));

        // Attempting to select unavailable topping 'Teri Medan' is rejected (Criteria #2)
        final optTeri = toppingGroup.options.firstWhere(
          (o) => o.code == 'teri',
        );
        state.toggleOption(toppingGroup, optTeri);
        expect(state.isOptionSelected(toppingGroup.id, optTeri.id), isFalse);

        // Increment quantity to 2
        state.incrementQuantity();
        expect(state.quantity, equals(2));
        expect(state.totalPrice, equals(70000)); // 35000 * 2
      },
    );

    testWidgets(
      'Criteria #3: ModifierConfigDialog rejects submission when required group is invalid',
      (tester) async {
        final nasgor = SampleMenuData.sampleMenus.firstWhere(
          (m) => m.id == 'm-nasgor-spesial',
        );

        // Create an unselected required state to test validation enforcement
        final unselectedState = ModifierSelectionState(menuItem: nasgor);
        final spiceGroup = SampleMenuData.spiceLevelGroup;
        // Force clear spice selection
        final currentOpt = spiceGroup.options.first;
        unselectedState.toggleOption(spiceGroup, currentOpt); // deselect

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: ModifierConfigDialog(
                item: nasgor,
                initialState: unselectedState,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify validation error message is shown
        expect(find.text('Wajib (Pilih 1)'), findsAtLeastNWidgets(1));

        // Tap an option (Level 2)
        await tester.tap(find.text('Level 2 (Pedas)'));
        await tester.pumpAndSettle();

        // Button becomes active
        expect(find.text('Tambah ke Pesanan'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #4: Search and category filter state is preserved on layout changes',
      (tester) async {
        final controller = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );

        controller.selectCategory('cat-minuman');
        controller.onSearchChanged('Jeruk', immediate: true);

        // Mobile Viewport
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildMenuTestApp(controller));
        await tester.pumpAndSettle();

        expect(find.text('Es Jeruk Peras'), findsOneWidget);
        expect(find.text('Es Teh Manis'), findsNothing);

        // Rotate to landscape / tablet
        tester.view.physicalSize = const Size(1024, 768);
        await tester.pumpAndSettle();

        // State is preserved
        expect(find.text('Es Jeruk Peras'), findsOneWidget);
        expect(find.text('Es Teh Manis'), findsNothing);
        expect(controller.selectedCategoryId, equals('cat-minuman'));
        expect(controller.searchQuery, equals('Jeruk'));
      },
    );

    testWidgets(
      'Criteria #5: Complete presentation states (Loading, Empty, Error)',
      (tester) async {
        final controller = mc.MenuController();

        // 1. Loading state
        await tester.pumpWidget(buildMenuTestApp(controller));
        expect(find.byType(AppLoadingState), findsOneWidget);

        // 2. Empty state
        controller.setCatalog(SampleMenuData.sampleCategories, []);
        await tester.pumpAndSettle();
        expect(find.byType(AppEmptyState), findsOneWidget);

        // 3. Error state with retry
        controller.setError('Gagal memuat daftar menu dari server.');
        await tester.pumpAndSettle();
        expect(find.byType(AppErrorState), findsOneWidget);
        expect(
          find.text('Gagal memuat daftar menu dari server.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criteria #5: Responsive layout on mobile and tablet without overflow',
      (tester) async {
        final controller = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );

        // Mobile
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildMenuTestApp(controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Tablet
        tester.view.physicalSize = const Size(1024, 768);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Spice level indicator renders fire icon for dishes with spice modifiers',
      (tester) async {
        final controller = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );

        await tester.pumpWidget(buildMenuTestApp(controller));
        await tester.pumpAndSettle();

        // Martabak Telur Spesial has spice_level modifier
        expect(find.byIcon(Icons.local_fire_department_rounded), findsWidgets);
      },
    );

    testWidgets('AppFeedback appears at the top and closes after one second', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      AppFeedback.show(
        capturedContext,
        message: 'Berhasil',
        type: AppBannerType.success,
      );
      await tester.pump();
      expect(find.byKey(const Key('app-feedback-success')), findsOneWidget);
      final top = tester.getTopLeft(
        find.byKey(const Key('app-feedback-success')),
      );
      expect(top.dy, lessThan(80));

      await tester.pump(const Duration(milliseconds: 999));
      expect(find.byKey(const Key('app-feedback-success')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const Key('app-feedback-success')), findsNothing);
    });
  });
}
