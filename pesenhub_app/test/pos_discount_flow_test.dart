import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:pesenhub_app/cart/controllers/cart_controller.dart';
import 'package:pesenhub_app/connectivity/connectivity_controller.dart';
import 'package:pesenhub_app/data/remote/api_config.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
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

    testWidgets('Loads discounts from real apiClient and enforces minimum spend', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final menuController = mc.MenuController(
        initialCategories: const [],
        initialMenus: const [itemMartabak],
      );
      final cartController = CartController();

      // Mock client that returns MERDEKA discount with min_order_amount 150.000
      final mockClient = http_testing.MockClient((req) async {
        if (req.url.path.contains('admin/discounts')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'disc-merdeka-1',
                  'name': 'MERDEKA',
                  'code': 'MDK-001',
                  'scope': 'ORDER',
                  'channel': 'ALL',
                  'type': 'FIXED',
                  'value': 20000,
                  'min_order_amount': 150000,
                  'is_active': true,
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"error":{"message":"not found"}}', 404);
      });

      final apiClient = PesenHubApiClient(
        config: ApiConfig(baseUri: Uri.parse('http://localhost:8080/api/v1/')),
        accessToken: () async => 'test-token',
        client: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: PosView(
              menuController: menuController,
              cartController: cartController,
              connectivityController: ConnectivityController(),
              apiClient: apiClient,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add 1 Martabak (Rp 60.000 < Rp 150.000)
      cartController.addItem(itemMartabak);
      await tester.pumpAndSettle();

      // Open promo sheet
      await tester.tap(find.byKey(const Key('cart-open-discount-button')));
      await tester.pumpAndSettle();

      // Real server promo is displayed
      expect(find.text('MERDEKA'), findsOneWidget);
      expect(find.text('Potongan Rp 20.000'), findsOneWidget);
      expect(find.text('Min. belanja Rp 150.000'), findsOneWidget);

      // Button is disabled because subtotal 60k < 150k
      final minBelanjaBtn = find.text('Min Belanja');
      expect(minBelanjaBtn, findsOneWidget);

      // Try typing manual code MDK-001
      await tester.enterText(
        find.byKey(const Key('promo-manual-code-input')),
        'MDK-001',
      );
      await tester.tap(find.byKey(const Key('promo-apply-manual-code-button')));
      await tester.pumpAndSettle();

      // Error message indicates minimum spend not reached
      expect(find.textContaining('Minimal belanja belum terpenuhi'), findsOneWidget);

      // Close sheet
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      // Now add 2 more martabaks: total = 3 * 60k = 180k >= 150k
      cartController.addItem(itemMartabak);
      cartController.addItem(itemMartabak);
      await tester.pumpAndSettle();
      expect(cartController.subtotalAmount, equals(180000));

      // Re-open promo sheet
      await tester.tap(find.byKey(const Key('cart-open-discount-button')));
      await tester.pumpAndSettle();

      // Now the button is active 'Gunakan'
      final applyBtn = find.byKey(const Key('promo-apply-disc-merdeka-1'));
      expect(applyBtn, findsOneWidget);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      // Verified: Applied discount Rp 20.000, Total = 180k - 20k = 160k!
      expect(cartController.appliedDiscount?.code, equals('MDK-001'));
      expect(cartController.discountAmount, equals(20000));
      expect(cartController.totalAmount, equals(160000));
    });
  });
}
