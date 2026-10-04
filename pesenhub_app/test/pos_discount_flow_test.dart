import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/cart/controllers/cart_controller.dart';
import 'package:pesenhub_app/connectivity/connectivity_controller.dart';
import 'package:pesenhub_app/menu/controllers/menu_controller.dart' as mc;
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:pesenhub_app/pos/pos_view.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  const itemMartabak = MenuItem(
    id: 'menu-martabak-1',
    categoryId: 'cat-1',
    name: 'Martabak Sapi Spesial',
    sku: 'MRT-SAPI-SP',
    priceAmount: 60000,
  );

  Widget buildPosApp({
    required mc.MenuController menuController,
    required CartController cartController,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: PosView(
          menuController: menuController,
          cartController: cartController,
          connectivityController: ConnectivityController(),
        ),
      ),
    );
  }

  group('POS Cart Discount & Promo Flow Tests', () {
    testWidgets('Cashier can apply and remove promo discount in POS cart', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 800); // Tablet viewport
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final menuController = mc.MenuController(
        initialCategories: const [],
        initialMenus: const [itemMartabak],
      );
      final cartController = CartController();

      await tester.pumpWidget(
        buildPosApp(
          menuController: menuController,
          cartController: cartController,
        ),
      );
      await tester.pumpAndSettle();

      // Add 1 Martabak (Rp 60.000)
      cartController.addItem(itemMartabak);
      await tester.pumpAndSettle();

      expect(cartController.subtotalAmount, equals(60000));
      expect(cartController.discountAmount, equals(0));
      expect(cartController.totalAmount, equals(60000));

      // Promo button is visible
      final openPromoBtn = find.byKey(const Key('cart-open-discount-button'));
      expect(openPromoBtn, findsOneWidget);

      // Tap 'Pakai Promo / Diskon'
      await tester.tap(openPromoBtn);
      await tester.pumpAndSettle();

      // Sheet opens
      expect(find.text('Pilih Promo / Diskon'), findsOneWidget);
      expect(find.text('Diskon Min Belanja 50 Ribu'), findsOneWidget);

      // Tap 'Gunakan' on Diskon Min Belanja 50 Ribu (value: 10.000)
      final promoApplyBtn = find.byKey(const Key('promo-apply-disc-fall-2'));
      expect(promoApplyBtn, findsOneWidget);
      await tester.tap(promoApplyBtn);
      await tester.pumpAndSettle();

      // Discount is applied: 60k - 10k = 50k
      expect(cartController.appliedDiscount, isNotNull);
      expect(cartController.discountAmount, equals(10000));
      expect(cartController.totalAmount, equals(50000));

      // Applied promo row appears in cart panel
      expect(find.text('Diskon Min Belanja 50 Ribu'), findsOneWidget);
      expect(find.text('Potongan: -Rp 10.000'), findsOneWidget);
      expect(find.text('Rp 50000'), findsOneWidget);

      // Tap remove discount button
      final removeBtn = find.byKey(const Key('cart-remove-discount-button'));
      expect(removeBtn, findsOneWidget);
      await tester.tap(removeBtn);
      await tester.pumpAndSettle();

      // Discount is cleared
      expect(cartController.appliedDiscount, isNull);
      expect(cartController.discountAmount, equals(0));
      expect(cartController.totalAmount, equals(60000));
      expect(
        find.byKey(const Key('cart-open-discount-button')),
        findsOneWidget,
      );
    });
  });
}
