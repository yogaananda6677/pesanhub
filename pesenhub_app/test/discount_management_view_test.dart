import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/settings/views/discount_management_view.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  Widget buildTestApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const DiscountManagementView(),
    );
  }

  group('DiscountManagementView Widget Tests', () {
    testWidgets('Renders header, hero banner, filters, and discount cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Kelola Diskon & Promo'), findsOneWidget);
      expect(find.text('Aturan & Strategi Promo'), findsOneWidget);
      expect(find.byKey(const Key('filter-scope-all')), findsOneWidget);
      expect(find.byKey(const Key('filter-scope-order')), findsOneWidget);
      expect(find.byKey(const Key('filter-scope-item')), findsOneWidget);
      expect(find.byKey(const Key('filter-channel-ALL')), findsOneWidget);

      // Default fallback promos
      expect(find.text('Promo GoFood Martabak 20%'), findsOneWidget);
      expect(find.text('Diskon Min Belanja 50 Ribu'), findsOneWidget);
      expect(find.text('Promo GrabFood Spesial 15%'), findsOneWidget);
    });

    testWidgets('Filters by Target Scope (ORDER vs ITEM)', (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap 'Total Belanja (Order)'
      final scopeOrderFinder = find.byKey(const Key('filter-scope-order'));
      await tester.ensureVisible(scopeOrderFinder);
      await tester.tap(scopeOrderFinder);
      await tester.pumpAndSettle();

      expect(find.text('Diskon Min Belanja 50 Ribu'), findsOneWidget);
      expect(find.text('Promo GrabFood Spesial 15%'), findsOneWidget);
      expect(find.text('Promo GoFood Martabak 20%'), findsNothing);

      // Tap 'Menu Spesifik (Item)'
      final scopeItemFinder = find.byKey(const Key('filter-scope-item'));
      await tester.ensureVisible(scopeItemFinder);
      await tester.tap(scopeItemFinder);
      await tester.pumpAndSettle();

      expect(find.text('Promo GoFood Martabak 20%'), findsOneWidget);
      expect(find.text('Diskon Min Belanja 50 Ribu'), findsNothing);
    });

    testWidgets('Filters by Merchant Channel', (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap 'GoFood'
      final gfFinder = find.byKey(const Key('filter-channel-GOFOOD'));
      await tester.ensureVisible(gfFinder);
      await tester.tap(gfFinder);
      await tester.pumpAndSettle();

      expect(find.text('Promo GoFood Martabak 20%'), findsOneWidget);
      expect(find.text('Diskon Min Belanja 50 Ribu'), findsNothing);
      expect(find.text('Promo GrabFood Spesial 15%'), findsNothing);
    });

    testWidgets('Opens Tambah Promo dialog and displays form', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap FloatingActionButton
      await tester.tap(find.byKey(const Key('add-promo-fab')));
      await tester.pumpAndSettle();

      expect(find.text('Tambah Promo Baru'), findsOneWidget);
      expect(find.text('Nama Promo / Diskon *'), findsOneWidget);
      expect(find.text('Target Promo *'), findsOneWidget);
      expect(find.text('Merchant / Saluran Penjualan *'), findsOneWidget);
      expect(find.text('Jenis Potongan *'), findsOneWidget);
      expect(find.text('Buat Promo'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      expect(find.text('Tambah Promo Baru'), findsNothing);
    });

    testWidgets('Creates promo with formatted dots in nominal value and min order', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-promo-fab')));
      await tester.pumpAndSettle();

      // Enter name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama Promo / Diskon *'),
        'Diskon Gajian 25 Ribu',
      );

      // Select Tipe Diskon = FIXED
      await tester.tap(find.text('Persentase (%)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nominal Tetap (Rp)').last);
      await tester.pumpAndSettle();

      // Enter nominal with dots
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nominal Potongan (Rp) *'),
        '25.000',
      );

      // Enter min order with dots
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minimal Pembelian (Rp, Opsional)'),
        '75.000',
      );

      // Save
      await tester.tap(find.text('Buat Promo'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed and new promo card rendered
      expect(find.text('Tambah Promo Baru'), findsNothing);
      expect(find.text('Diskon Gajian 25 Ribu'), findsOneWidget);
      expect(find.text('Rp 25.000'), findsOneWidget);
      expect(find.text('Min. belanja Rp 75.000'), findsOneWidget);
    });

    testWidgets('Validates item scope requires selecting menu items', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-promo-fab')));
      await tester.pumpAndSettle();

      // Enter name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama Promo / Diskon *'),
        'Diskon Martabak Manis',
      );

      // Change Scope to ITEM
      await tester.tap(find.text('Total Pembelian (Semua Pesanan)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menu Tertentu (Spesifik Menu)').last);
      await tester.pumpAndSettle();

      // Should show menu selector section
      expect(find.text('Menu Diskon (0) *'), findsOneWidget);
      expect(find.byKey(const Key('open-menu-picker-button')), findsOneWidget);

      // Enter value
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Besar Diskon (%) *'),
        '15',
      );

      // Try saving without picking any menu
      await tester.tap(find.text('Buat Promo'));
      await tester.pumpAndSettle();

      // Should show validation error and stay in dialog
      expect(
        find.text('Pilih minimal 1 menu untuk promo menu tertentu!'),
        findsOneWidget,
      );
      expect(find.text('Tambah Promo Baru'), findsOneWidget);
    });
  });
}
