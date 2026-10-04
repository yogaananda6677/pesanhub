import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/cart/controllers/cart_controller.dart';
import 'package:pesenhub_app/discount/models/discount.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';

void main() {
  group('CartController Discount Calculation Tests', () {
    late CartController cart;
    const itemMartabak = MenuItem(
      id: 'menu-martabak-1',
      categoryId: 'cat-1',
      name: 'Martabak Sapi Spesial',
      sku: 'MRT-SAPI-SP',
      priceAmount: 50000,
    );
    const itemTerangBulan = MenuItem(
      id: 'menu-tb-1',
      categoryId: 'cat-2',
      name: 'Terang Bulan Coklat Keju',
      sku: 'TB-CK-01',
      priceAmount: 30000,
    );

    setUp(() {
      cart = CartController();
    });

    test('Order Scope Percentage with Cap', () {
      cart.addItem(itemMartabak); // 50k
      cart.addItem(itemTerangBulan); // 30k -> subtotal 80k

      expect(cart.subtotalAmount, equals(80000));
      expect(cart.discountAmount, equals(0));
      expect(cart.totalAmount, equals(80000));

      final discount = Discount(
        id: 'disc-50-cap-10',
        name: 'Diskon 50% Max 10rb',
        scope: 'ORDER',
        channel: 'ALL',
        type: 'PERCENTAGE',
        value: 50,
        maxDiscountAmount: 10000,
        minOrderAmount: 50000,
      );

      cart.applyDiscount(discount);

      expect(cart.appliedDiscount, equals(discount));
      // 50% of 80k is 40k, capped at 10k
      expect(cart.discountAmount, equals(10000));
      expect(cart.totalAmount, equals(70000));

      // Removing discount resets
      cart.removeDiscount();
      expect(cart.appliedDiscount, isNull);
      expect(cart.discountAmount, equals(0));
      expect(cart.totalAmount, equals(80000));
    });

    test('Order Scope Fixed Amount', () {
      cart.addItem(itemMartabak); // 50k

      final discount = Discount(
        id: 'disc-fixed-15',
        name: 'Potongan 15.000',
        scope: 'ORDER',
        channel: 'ALL',
        type: 'FIXED',
        value: 15000,
        minOrderAmount: 40000,
      );

      cart.applyDiscount(discount);
      expect(cart.discountAmount, equals(15000));
      expect(cart.totalAmount, equals(35000));
    });

    test('Item Scope Discount applies only to target items', () {
      cart.addItem(itemMartabak); // 50k (eligible)
      cart.addItem(itemTerangBulan); // 30k (not eligible)
      // subtotal 80k

      final discount = Discount(
        id: 'disc-martabak-20',
        name: 'Diskon Martabak 20%',
        scope: 'ITEM',
        channel: 'ALL',
        type: 'PERCENTAGE',
        value: 20,
        menuIds: ['menu-martabak-1'],
      );

      cart.applyDiscount(discount);

      // 20% of 50k = 10k (only martabak is eligible)
      expect(cart.discountAmount, equals(10000));
      expect(cart.totalAmount, equals(70000));
    });

    test('Channel Specific Discount (GoFood only)', () {
      cart.addItem(itemMartabak); // 50k

      final gfDiscount = Discount(
        id: 'disc-gf-only',
        name: 'Diskon Khusus GoFood',
        scope: 'ORDER',
        channel: 'GOFOOD',
        type: 'FIXED',
        value: 10000,
      );

      cart.applyDiscount(gfDiscount);

      // Default order source is CASHIER_MANUAL -> should NOT apply
      expect(cart.orderSource, equals('CASHIER_MANUAL'));
      expect(cart.discountAmount, equals(0));
      expect(cart.totalAmount, equals(50000));

      // Switch to GOFOOD -> should apply
      cart.setOrderSource('GOFOOD');
      expect(cart.discountAmount, equals(10000));
      expect(cart.totalAmount, equals(40000));

      // Switch to GRABFOOD -> should NOT apply
      cart.setOrderSource('GRABFOOD');
      expect(cart.discountAmount, equals(0));
      expect(cart.totalAmount, equals(50000));
    });

    test('Minimum spend requirement', () {
      cart.addItem(itemTerangBulan); // 30k

      final minSpendDiscount = Discount(
        id: 'disc-min-50',
        name: 'Diskon Min 50rb',
        scope: 'ORDER',
        channel: 'ALL',
        type: 'FIXED',
        value: 10000,
        minOrderAmount: 50000,
      );

      cart.applyDiscount(minSpendDiscount);

      // 30k < 50k -> 0 discount
      expect(cart.discountAmount, equals(0));
      expect(cart.totalAmount, equals(30000));

      // Add another item to reach 80k
      cart.addItem(itemMartabak); // +50k = 80k
      expect(cart.subtotalAmount, equals(80000));
      expect(cart.discountAmount, equals(10000));
      expect(cart.totalAmount, equals(70000));
    });

    test('Draft includes discount information in JSON', () {
      cart.setCustomerName('Budi');
      cart.addItem(itemMartabak); // 50k

      final discount = Discount(
        id: 'disc-test-1',
        name: 'Promo 10k',
        scope: 'ORDER',
        channel: 'ALL',
        type: 'FIXED',
        value: 10000,
      );
      cart.applyDiscount(discount);

      final draft = cart.currentDraft;
      expect(draft.discountId, equals('disc-test-1'));
      expect(draft.discountAmount, equals(10000));
      expect(draft.discountName, equals('Promo 10k'));
      expect(draft.subtotalAmount, equals(50000));
      expect(draft.totalAmount, equals(40000));

      final json = draft.toJson();
      expect(json['discount_id'], equals('disc-test-1'));
      expect(json['discount_amount'], equals(10000));
      expect(json['discount_name'], equals('Promo 10k'));
      expect(json['subtotal_amount'], equals(50000));
      expect(json['total_amount'], equals(40000));
    });
  });
}
