import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/settings/views/contact_rules_view.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  Widget buildTestApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const ContactRulesView(),
    );
  }

  group('ContactRulesView Widget Tests', () {
    testWidgets('Renders header, hero banner, filters, and default contacts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Filter Kontak & Aturan Chat AI'), findsOneWidget);
      expect(find.text('Aturan Kontak & Filter Chat'), findsOneWidget);
      expect(find.byKey(const Key('filter-contact-ALL')), findsOneWidget);
      expect(find.byKey(const Key('filter-contact-CUSTOMER')), findsOneWidget);
      expect(
        find.byKey(const Key('filter-contact-NON_CUSTOMER')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('filter-contact-OTHER')), findsOneWidget);

      // Verify default fallback contacts
      expect(find.text('Budi Santoso'), findsOneWidget);
      expect(find.text('Toko Sumber Telur'), findsOneWidget);
      expect(find.text('Pak RT Lingkungan'), findsOneWidget);
    });

    testWidgets('Filters contacts using category chips', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap Pelanggan chip
      await tester.tap(find.byKey(const Key('filter-contact-CUSTOMER')));
      await tester.pumpAndSettle();

      expect(find.text('Budi Santoso'), findsOneWidget);
      expect(find.text('Toko Sumber Telur'), findsNothing);
      expect(find.text('Pak RT Lingkungan'), findsNothing);

      // Tap Bukan Pelanggan chip
      await tester.tap(find.byKey(const Key('filter-contact-NON_CUSTOMER')));
      await tester.pumpAndSettle();

      expect(find.text('Budi Santoso'), findsNothing);
      expect(find.text('Toko Sumber Telur'), findsOneWidget);
      expect(find.text('Pak RT Lingkungan'), findsNothing);

      // Tap Supplier / Internal chip
      await tester.tap(find.byKey(const Key('filter-contact-OTHER')));
      await tester.pumpAndSettle();

      expect(find.text('Pak RT Lingkungan'), findsOneWidget);
      expect(find.text('Budi Santoso'), findsNothing);
    });

    testWidgets('Searches contacts by keyword', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Telur');
      await tester.pumpAndSettle();

      expect(find.text('Toko Sumber Telur'), findsOneWidget);
      expect(find.text('Budi Santoso'), findsNothing);
      expect(find.text('Pak RT Lingkungan'), findsNothing);
    });

    testWidgets('Toggles auto-reply switch on a contact', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('AI Balas Otomatis: AKTIF'), findsOneWidget);

      final toggleFinder = find.byKey(const Key('toggle-reply-c-1'));
      expect(toggleFinder, findsOneWidget);

      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      // Verified switch turned off
      expect(find.text('AI Balas: NONAKTIF'), findsNWidgets(3));
    });

    testWidgets('Opens Tandai dialog and updates contact classification', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open mark dialog for Budi Santoso (c-1)
      final markBtn = find.byKey(const Key('mark-contact-button-c-1'));
      await tester.ensureVisible(markBtn);
      await tester.tap(markBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Tandai Kontak:'), findsOneWidget);
      expect(find.byKey(const Key('save-mark-contact-button')), findsOneWidget);

      // Save changes (default classification for customer changes to NON_CUSTOMER)
      await tester.tap(find.byKey(const Key('save-mark-contact-button')));
      await tester.pumpAndSettle();

      // Budi Santoso now has "Bukan Pelanggan" classification (1 filter chip + 2 card badges)
      expect(find.text('Bukan Pelanggan'), findsNWidgets(3));
    });

    testWidgets('Opens Tambah Kontak Manual dialog and adds new contact', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byKey(const Key('add-contact-fab')));
      await tester.pumpAndSettle();

      expect(find.text('Tambah Kontak WhatsApp'), findsOneWidget);

      // Fill in fields
      await tester.enterText(
        find.byKey(const Key('input-contact-phone')),
        '081299991111',
      );
      await tester.enterText(
        find.byKey(const Key('input-contact-name')),
        'Supplier Kardus Box',
      );
      await tester.enterText(
        find.byKey(const Key('input-contact-notes')),
        'Penyedia packaging martabak',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('submit-add-contact-button')));
      await tester.pumpAndSettle();

      expect(find.text('Supplier Kardus Box'), findsOneWidget);
    });
  });
}
