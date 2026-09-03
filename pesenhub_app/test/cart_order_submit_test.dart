import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/cart/controllers/cart_controller.dart';
import 'package:pesenhub_app/cart/widgets/order_review_dialog.dart';
import 'package:pesenhub_app/cart/widgets/order_success_dialog.dart';
import 'package:pesenhub_app/menu/controllers/modifier_selection_state.dart';
import 'package:pesenhub_app/menu/models/sample_menu_data.dart';
import 'package:pesenhub_app/pos/pos_view.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';

void main() {
  group('Issue #28: Cart, Takeaway Notes, Order Review, and Manual Submit Tests', () {
    test(
      'Criteria #1: Cart items, modifiers, takeaway notes, and subtotal calculation',
      () {
        final controller = CartController();
        final nasgor = SampleMenuData.sampleMenus.firstWhere(
          (m) => m.id == 'm-nasgor-spesial',
        );
        final modifierState = ModifierSelectionState(menuItem: nasgor);

        // Add topping Telur Ceplok (+4000)
        final toppingGroup = SampleMenuData.toppingGroup;
        final optCeplok = toppingGroup.options.firstWhere(
          (o) => o.code == 'ceplok',
        );
        modifierState.toggleOption(toppingGroup, optCeplok);
        modifierState.setNotes('Tanpa bawang goreng');

        controller.addItemFromModifierState(nasgor, modifierState);
        controller.setCustomerName('Pak Joko');
        controller.setTakeaway(true);
        controller.setTakeawayNotes('Pisah kuah & sambal');

        expect(controller.totalItemCount, equals(1));
        expect(controller.subtotalAmount, equals(29000));
        expect(controller.isTakeaway, isTrue);
        expect(controller.takeawayNotes, equals('Pisah kuah & sambal'));

        // Update quantity to 2
        final itemId = controller.items.first.id;
        controller.updateQuantity(itemId, 2);
        expect(controller.totalItemCount, equals(2));
        expect(controller.subtotalAmount, equals(58000));

        // Remove item
        controller.removeItem(itemId);
        expect(controller.totalItemCount, equals(0));
        expect(controller.isEmpty, isTrue);
      },
    );

    testWidgets(
      'Criteria #1: OrderReviewDialog displays full review before submit',
      (tester) async {
        final controller = CartController();
        final nasgor = SampleMenuData.sampleMenus.firstWhere(
          (m) => m.id == 'm-nasgor-spesial',
        );
        final modifierState = ModifierSelectionState(menuItem: nasgor);
        controller.addItemFromModifierState(nasgor, modifierState);
        controller.setCustomerName('Ibu Siti');
        controller.setTakeaway(true);
        controller.setTakeawayNotes('Bungkus rapi');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: OrderReviewDialog(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Review Pesanan Kasir'), findsOneWidget);
        expect(find.text('Ibu Siti'), findsOneWidget);
        expect(find.text('Bungkus / Takeaway'), findsOneWidget);
        expect(find.text('Catatan Kemasan: Bungkus rapi'), findsOneWidget);
        expect(find.text('1x Nasi Goreng Spesial'), findsOneWidget);
        expect(find.text('Rp 25000'), findsAtLeastNWidgets(1));
        expect(find.text('Kirim & Buat Pesanan'), findsOneWidget);
      },
    );

    test(
      'Criteria #2: Double-tap locked and retry uses exact same idempotency key',
      () async {
        final controller = CartController();
        final nasgor = SampleMenuData.sampleMenus.firstWhere(
          (m) => m.id == 'm-nasgor-spesial',
        );
        final modifierState = ModifierSelectionState(menuItem: nasgor);
        controller.addItemFromModifierState(nasgor, modifierState);
        controller.setCustomerName('Mas Danang');

        final initialIdempotencyKey = controller.idempotencyKey;
        final initialClientOrderId = controller.clientOrderId;

        int callCount = 0;
        // Simulated submit function that fails on first call
        Future<QueueOrder> failingSubmit(draft) async {
          callCount++;
          throw Exception('Simulated network timeout');
        }

        // First attempt (fails)
        final result1 = await controller.submitOrder(submitFn: failingSubmit);
        expect(result1, isNull);
        expect(callCount, equals(1));
        expect(controller.errorMessage, contains('Simulated network timeout'));

        // Crucial: Idempotency Key MUST be preserved for retry!
        expect(controller.idempotencyKey, equals(initialIdempotencyKey));
        expect(controller.clientOrderId, equals(initialClientOrderId));

        // Retry attempt (succeeds)
        Future<QueueOrder> successSubmit(draft) async {
          callCount++;
          expect(draft.idempotencyKey, equals(initialIdempotencyKey));
          return QueueOrder(
            id: 'ord-123',
            orderNumber: 'ORD-TEST123',
            customerName: draft.customerName,
            customerPhone: '',
            source: 'CASHIER_MANUAL',
            orderStatus: 'PENDING',
            paymentStatus: 'UNPAID',
            createdAt: DateTime.now(),
            version: 1,
          );
        }

        final result2 = await controller.submitOrder(submitFn: successSubmit);
        expect(result2, isNotNull);
        expect(result2!.orderNumber, equals('ORD-TEST123'));
        expect(callCount, equals(2));

        // After successful creation, fresh keys generated for subsequent orders
        expect(controller.idempotencyKey, isNot(equals(initialIdempotencyKey)));
      },
    );

    testWidgets(
      'Criteria #3: Backend availability / price discrepancy prompts confirmation banner',
      (tester) async {
        final controller = CartController();
        final nasgor = SampleMenuData.sampleMenus.firstWhere(
          (m) => m.id == 'm-nasgor-spesial',
        );
        final modifierState = ModifierSelectionState(menuItem: nasgor);
        controller.addItemFromModifierState(nasgor, modifierState);
        controller.setCustomerName('Budi');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: OrderReviewDialog(
                controller: controller,
                submitFn: (draft) async {
                  throw Exception('menu or modifier unavailable (habis)');
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap submit
        await tester.tap(find.text('Kirim & Buat Pesanan'));
        await tester.pumpAndSettle();

        // Discrepancy banner is displayed
        expect(find.byType(AppBanner), findsOneWidget);
        expect(
          find.textContaining('Perubahan ketersediaan atau harga'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criteria #4: Submit button disabled while isSubmitting is active',
      (tester) async {
        final controller = CartController();
        final nasgor = SampleMenuData.sampleMenus.firstWhere(
          (m) => m.id == 'm-nasgor-spesial',
        );
        final modifierState = ModifierSelectionState(menuItem: nasgor);
        controller.addItemFromModifierState(nasgor, modifierState);
        controller.setCustomerName('Budi');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: OrderReviewDialog(
                controller: controller,
                submitFn: (draft) async {
                  await Future.delayed(const Duration(milliseconds: 100));
                  return QueueOrder(
                    id: 'ord-async',
                    orderNumber: 'ORD-ASYNC',
                    customerName: draft.customerName,
                    customerPhone: '',
                    source: 'CASHIER_MANUAL',
                    orderStatus: 'PENDING',
                    paymentStatus: 'UNPAID',
                    createdAt: DateTime.now(),
                    version: 1,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap submit
        await tester.tap(find.text('Kirim & Buat Pesanan'));
        await tester.pump(); // Start async work

        // Button is now disabled and displays loading text
        expect(find.text('Memproses Pesanan...'), findsOneWidget);

        await tester.pumpAndSettle(); // Finish async work
      },
    );

    testWidgets(
      'Criteria #5: OrderSuccessDialog shows receipt summary and actions',
      (tester) async {
        final order = QueueOrder(
          id: 'ord-success',
          orderNumber: 'ORD-MANUAL-001',
          customerName: 'Pak Wahyu',
          customerPhone: '08123456789',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PENDING',
          paymentStatus: 'UNPAID',
          isTakeaway: true,
          createdAt: DateTime.now(),
          version: 1,
        );

        bool viewQueueTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: OrderSuccessDialog(
                order: order,
                onViewQueue: () => viewQueueTapped = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pesanan Berhasil Dibuat!'), findsOneWidget);
        expect(find.text('ORD-MANUAL-001'), findsOneWidget);
        expect(find.text('Pak Wahyu'), findsOneWidget);
        expect(find.text('Bungkus / Takeaway'), findsOneWidget);

        await tester.tap(find.text('Lihat di Antrean'));
        expect(viewQueueTapped, isTrue);
      },
    );

    testWidgets(
      'Criteria #5: Responsive PosView renders on mobile and tablet without overflow',
      (tester) async {
        final controller = CartController();

        // Mobile Viewport (< 600dp)
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: PosView(cartController: controller)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Add item to cart
        final nasgor = SampleMenuData.sampleMenus.first;
        final modState = ModifierSelectionState(menuItem: nasgor);
        controller.addItemFromModifierState(nasgor, modState);
        await tester.pumpAndSettle();

        // Sticky bar rendered on mobile
        expect(find.text('Review Pesanan'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Tablet Viewport (>= 600dp) -> Split screen
        tester.view.physicalSize = const Size(1024, 768);
        await tester.pumpAndSettle();

        expect(find.text('Keranjang (1)'), findsOneWidget);
        expect(find.text('Review & Proses Pesanan'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
