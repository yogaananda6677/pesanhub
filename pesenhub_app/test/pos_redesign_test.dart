import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/cart/controllers/cart_controller.dart';
import 'package:pesenhub_app/connectivity/connectivity_controller.dart';
import 'package:pesenhub_app/menu/controllers/menu_controller.dart' as mc;
import 'package:pesenhub_app/menu/controllers/modifier_selection_state.dart';
import 'package:pesenhub_app/menu/models/sample_menu_data.dart';
import 'package:pesenhub_app/menu/widgets/menu_category_filter.dart';
import 'package:pesenhub_app/menu/widgets/menu_item_card.dart';
import 'package:pesenhub_app/pos/pos_view.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/connectivity_badge.dart';

void main() {
  Widget buildPosApp({
    mc.MenuController? menuController,
    CartController? cartController,
    ConnectivityController? connectivityController,
    Future<QueueOrder> Function(dynamic draft)? submitOrder,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: PosView(
          menuController: menuController,
          cartController: cartController,
          connectivityController: connectivityController,
          submitOrder: submitOrder,
        ),
      ),
    );
  }

  group('Issue #133: POS Redesign with Category Tabs & Sticky Bottom Cart', () {
    testWidgets(
      '1. Mobile Header: Displays search bar, connectivity badge, and horizontal category tabs',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final menuController = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );
        final connectivityController = ConnectivityController();

        await tester.pumpWidget(
          buildPosApp(
            menuController: menuController,
            connectivityController: connectivityController,
          ),
        );
        await tester.pumpAndSettle();

        // Search bar is displayed in compact header
        expect(
          find.widgetWithText(
            TextField,
            'Cari menu (Nasi Goreng, Es Teh, SKU)...',
          ),
          findsOneWidget,
        );

        // Connectivity badge is displayed in compact header
        expect(find.byType(ConnectivityBadge), findsOneWidget);

        // Horizontal category tabs are displayed
        expect(find.text('Semua (6)'), findsOneWidget);
        expect(find.text('Makanan (3)'), findsOneWidget);
        expect(find.text('Minuman (2)'), findsOneWidget);

        // Minimum 48dp touch target on category tab
        final tabSize = tester.getSize(
          find.byKey(const ValueKey('category_tab_ALL')),
        );
        expect(tabSize.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      '2. Category Switching: Preserves cart items and search state when switching tabs',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final menuController = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );
        final cartController = CartController();

        await tester.pumpWidget(
          buildPosApp(
            menuController: menuController,
            cartController: cartController,
          ),
        );
        await tester.pumpAndSettle();

        // Add a menu item to cart
        final nasgor = SampleMenuData.sampleMenus.first;
        final modState = ModifierSelectionState(menuItem: nasgor);
        cartController.addItemFromModifierState(nasgor, modState);
        cartController.setCustomerName('Budi Test');
        await tester.pumpAndSettle();

        expect(cartController.totalItemCount, equals(1));
        expect(cartController.customerName, equals('Budi Test'));

        // Search for item
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Cari menu (Nasi Goreng, Es Teh, SKU)...',
          ),
          'Teh',
        );
        await tester.pumpAndSettle();

        expect(menuController.searchQuery, equals('Teh'));

        // Switch category tab to Minuman
        await tester.scrollUntilVisible(
          find.text('Minuman (2)'),
          50.0,
          scrollable: find.descendant(
            of: find.byType(MenuCategoryFilter),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Minuman (2)'));
        await tester.pumpAndSettle();

        // Cart items and customer name are fully preserved!
        expect(cartController.totalItemCount, equals(1));
        expect(cartController.customerName, equals('Budi Test'));
        expect(
          cartController.items.first.menuItem.name,
          equals('Nasi Goreng Spesial'),
        );

        // Search query is preserved
        expect(menuController.searchQuery, equals('Teh'));
        expect(find.text('Es Teh Manis'), findsOneWidget);

        // Return to Semua
        await tester.scrollUntilVisible(
          find.text('Semua (6)'),
          -50.0,
          scrollable: find.descendant(
            of: find.byType(MenuCategoryFilter),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Semua (6)'));
        await tester.pumpAndSettle();

        expect(cartController.totalItemCount, equals(1));
      },
    );

    testWidgets(
      '3. Mobile Catalog Focus: Menu cards immediately visible, unavailable item disabled',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final menuController = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );

        await tester.pumpWidget(buildPosApp(menuController: menuController));
        await tester.pumpAndSettle();

        // Menu cards are visible at the top without scrolling past customer card
        expect(find.text('Nasi Goreng Spesial'), findsOneWidget);
        expect(find.text('Nasi Goreng Gila'), findsOneWidget);

        // Unavailable item shows Habis badge
        expect(find.text('Nasi Goreng Seafood'), findsOneWidget);
        expect(find.text('Habis'), findsOneWidget);

        // Unavailable item cannot be tapped
        final unavailableCard = find.widgetWithText(
          MenuItemCard,
          'Nasi Goreng Seafood',
        );
        await tester.tap(unavailableCard);
        await tester.pumpAndSettle();

        // Cart remains empty
        expect(find.byKey(const Key('sticky-cart-summary')), findsNothing);
      },
    );

    testWidgets(
      '4. Sticky Bottom Cart Bar: Appears on item add, displays count & total, opens sheet',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cartController = CartController();

        await tester.pumpWidget(buildPosApp(cartController: cartController));
        await tester.pumpAndSettle();

        // Cart is empty initially -> sticky bar is hidden
        expect(find.byKey(const Key('sticky-cart-summary')), findsNothing);
        expect(find.text('Review Pesanan'), findsNothing);

        // Add 1 item
        final nasgor = SampleMenuData.sampleMenus.first;
        final modState = ModifierSelectionState(menuItem: nasgor);
        cartController.addItemFromModifierState(nasgor, modState);
        await tester.pumpAndSettle();

        // Sticky bar appears
        expect(find.byKey(const Key('sticky-cart-summary')), findsOneWidget);
        expect(find.text('1 Item di Keranjang'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('sticky-cart-summary')),
            matching: find.text('Rp 25000'),
          ),
          findsOneWidget,
        );
        expect(find.text('Review Pesanan'), findsOneWidget);

        // Minimum 48dp touch target
        final reviewButtonSize = tester.getSize(
          find.byKey(const Key('sticky-cart-review-button')),
        );
        expect(reviewButtonSize.height, greaterThanOrEqualTo(48.0));

        // Tap sticky bar opens mobile cart sheet
        await tester.tap(find.byKey(const Key('sticky-cart-summary')));
        await tester.pumpAndSettle();

        // Bottom sheet is visible with customer identity fields
        expect(find.text('Identitas Pelanggan'), findsOneWidget);
        expect(find.text('Nama Pelanggan *'), findsOneWidget);
        expect(find.text('Nomor WhatsApp (Opsional)'), findsOneWidget);
        expect(find.text('Bungkus / Takeaway'), findsOneWidget);
        expect(find.text('Daftar Menu Pesanan'), findsOneWidget);
        expect(find.text('Review & Proses Pesanan'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Checkout Flow in Bottom Sheet: Validation on empty customer name and submit success',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cartController = CartController();
        final nasgor = SampleMenuData.sampleMenus.first;
        final modState = ModifierSelectionState(menuItem: nasgor);
        cartController.addItemFromModifierState(nasgor, modState);

        bool submitCalled = false;
        Future<QueueOrder> dummySubmit(draft) async {
          submitCalled = true;
          return QueueOrder(
            id: 'ord-test-01',
            orderNumber: 'ORD-TEST-001',
            customerName: draft.customerName,
            customerPhone: draft.customerPhone ?? '',
            source: 'CASHIER_MANUAL',
            orderStatus: 'PENDING',
            paymentStatus: 'UNPAID',
            isTakeaway: draft.isTakeaway,
            createdAt: DateTime.now(),
            version: 1,
          );
        }

        await tester.pumpWidget(
          buildPosApp(cartController: cartController, submitOrder: dummySubmit),
        );
        await tester.pumpAndSettle();

        // Open bottom sheet
        await tester.tap(find.byKey(const Key('sticky-cart-review-button')));
        await tester.pumpAndSettle();

        // 1. Tapping submit when customer name is empty blocks submission
        await tester.tap(find.text('Review & Proses Pesanan'));
        await tester.pumpAndSettle();

        expect(
          find.text('Masukkan nama pelanggan sebelum melanjutkan pembayaran.'),
          findsOneWidget,
        );
        expect(submitCalled, isFalse);

        // 2. Enter customer name
        await tester.enterText(
          find.widgetWithText(TextField, 'Contoh: Budi Santoso'),
          'Ahmad Kasir',
        );
        await tester.pumpAndSettle();

        // 3. Toggle takeaway
        await tester.tap(find.text('Bungkus / Takeaway'));
        await tester.pumpAndSettle();

        expect(find.text('Catatan Kemasan Bungkus'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Misal: Pisah kuah, sambal dipisah...',
          ),
          'Pisah sambal',
        );
        await tester.pumpAndSettle();

        // 4. Submit now succeeds
        await tester.tap(find.text('Review & Proses Pesanan'));
        await tester.pumpAndSettle();

        // Review dialog opens
        expect(find.text('Review Pesanan Kasir'), findsOneWidget);
        expect(find.text('Ahmad Kasir'), findsOneWidget);
        expect(find.text('Bungkus / Takeaway'), findsOneWidget);

        // Kirim & Buat Pesanan
        await tester.tap(find.text('Kirim & Buat Pesanan'));
        await tester.pumpAndSettle();

        // Success dialog shown
        expect(find.text('Pesanan Berhasil Dibuat!'), findsOneWidget);
        expect(find.text('ORD-TEST-001'), findsOneWidget);
        expect(submitCalled, isTrue);

        // Cart is cleared
        expect(cartController.totalItemCount, equals(0));
      },
    );

    testWidgets(
      '6. Tablet Split View: Renders catalog on left and live cart on right without overflow',
      (tester) async {
        // Tablet viewport
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cartController = CartController();
        final menuController = mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );

        await tester.pumpWidget(
          buildPosApp(
            menuController: menuController,
            cartController: cartController,
          ),
        );
        await tester.pumpAndSettle();

        // Split view elements are visible simultaneously
        expect(find.text('Keranjang (0)'), findsOneWidget);
        expect(find.text('Identitas Pelanggan'), findsOneWidget);
        expect(find.text('Semua (6)'), findsOneWidget);

        // Add item
        final nasgor = SampleMenuData.sampleMenus.first;
        final modState = ModifierSelectionState(menuItem: nasgor);
        cartController.addItemFromModifierState(nasgor, modState);
        await tester.pumpAndSettle();

        expect(find.text('Keranjang (1)'), findsOneWidget);
        expect(find.text('Review & Proses Pesanan'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '7. Responsive & Accessibility: Zero RenderFlex overflow on 360x800, 390x844, 768x1024, 1280x800 with TextScale 1.0 & 2.0',
      (tester) async {
        final viewports = [
          const Size(360, 800), // Small mobile
          const Size(390, 844), // Standard mobile
          const Size(768, 1024), // Portrait tablet
          const Size(1280, 800), // Landscape tablet
        ];

        final textScales = [1.0, 2.0];

        for (final vp in viewports) {
          for (final scale in textScales) {
            tester.view.physicalSize = vp;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final cartController = CartController();
            final nasgor = SampleMenuData.sampleMenus.first;
            final modState = ModifierSelectionState(menuItem: nasgor);
            cartController.addItemFromModifierState(nasgor, modState);
            cartController.setCustomerName('Uji Responsif');

            await tester.pumpWidget(
              buildPosApp(cartController: cartController, textScale: scale),
            );
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason: 'Overflow on viewport $vp with text scale $scale',
            );
          }
        }
      },
    );
  });
}
