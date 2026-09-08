import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/navigation/app_destination.dart';
import 'package:pesenhub_app/shell/app_shell.dart';
import 'package:pesenhub_app/shell/destination_views.dart';
import 'package:pesenhub_app/showcase/design_system_showcase.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  group('Issue #24 and #121: Responsive App Shell Tests', () {
    testWidgets(
      'Criteria #1: Mobile viewport (< 600dp) renders NavigationBar without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const AppShell()),
        );

        // Verify mobile shell renders bottom NavigationBar
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);

        // Mobile keeps all five operational destinations directly without Lainnya sheet.
        for (final destination in AppDestination.values) {
          expect(find.text(destination.label), findsOneWidget);
        }
        final navigationBar = tester.widget<NavigationBar>(
          find.byKey(const Key('primary-bottom-navigation')),
        );
        expect(navigationBar.destinations, hasLength(5));

        // Verify no exceptions or overflows
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Criteria #1: Tablet viewport (>= 600dp) renders NavigationRail without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const AppShell()),
        );

        // Verify tablet shell renders left NavigationRail
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);

        // Verify all destination labels in rail
        for (final destination in AppDestination.values) {
          expect(find.text(destination.label), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Criteria #2: Changing orientation preserves active destination',
      (tester) async {
        // Start in portrait (400 x 800)
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const AppShell()),
        );

        // Navigate to 'Antrean' (index 2)
        await tester.tap(find.text('Antrean'));
        await tester.pumpAndSettle();

        expect(find.text('Antrean Dapur'), findsOneWidget);
        expect(find.byType(QueueDestinationView), findsOneWidget);

        // Rotate device to landscape (800 x 400)
        tester.view.physicalSize = const Size(800, 400);
        await tester.pumpAndSettle();

        // Verify Antrean destination remains active after rotation/resize
        expect(find.text('Antrean Dapur'), findsOneWidget);
        expect(find.byType(QueueDestinationView), findsOneWidget);
        expect(find.byType(NavigationRail), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #2: Input state is preserved when switching between mobile and tablet',
      (tester) async {
        // Start on POS destination in mobile size (400 x 700)
        tester.view.physicalSize = const Size(400, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AppShell(initialIndex: 1),
          ),
        );

        // Enter search text in POS mobile view
        final searchField = find.widgetWithText(
          TextField,
          'Cari menu (Nasi Goreng, Es Teh, SKU)...',
        );
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, 'Nasi Goreng');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Nasi Goreng'), findsOneWidget);

        // Expand to tablet size (900 x 700)
        tester.view.physicalSize = const Size(900, 700);
        await tester.pumpAndSettle();

        // Verify entered search query is retained
        expect(find.text('Nasi Goreng'), findsOneWidget);

        // Enter customer name in tablet split view
        final nameField = find.widgetWithText(
          TextField,
          'Contoh: Budi Santoso',
        );
        expect(nameField, findsOneWidget);
        await tester.enterText(nameField, 'Pak Bambang Sukses');
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Pak Bambang Sukses'), findsOneWidget);
        // Switch back to mobile size (400 x 700)
        tester.view.physicalSize = const Size(400, 700);
        await tester.pumpAndSettle();

        // Verify search query is still retained
        expect(find.text('Nasi Goreng'), findsOneWidget);

        // Switch back to tablet size (900 x 700) and verify customer name retained
        tester.view.physicalSize = const Size(900, 700);
        await tester.pumpAndSettle();

        // Verify entered customer name is retained in the form
        expect(find.text('Pak Bambang Sukses'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #3: Keyboard insets do not cause overflow and primary action remains scrollable',
      (tester) async {
        tester.view.physicalSize = const Size(400, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AppShell(initialIndex: 1),
          ),
        );

        // Simulate keyboard open by setting bottom viewInsets
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        // Verify no RenderFlex overflow
        expect(tester.takeException(), isNull);

        // Verify content is in the tree and can be scrolled into view without overflow
        final itemFinder = find.text('Nasi Goreng Spesial');
        expect(itemFinder, findsOneWidget);

        await tester.scrollUntilVisible(
          itemFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(itemFinder, findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #4: Navigation switching works across all destinations',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const AppShell()),
        );

        // 1. Initially on Ringkasan (Dashboard)
        expect(find.text('Ringkasan Operasional'), findsOneWidget);

        // 2. Switch to Kasir
        await tester.tap(find.text('Kasir'));
        await tester.pumpAndSettle();
        expect(find.byType(PosDestinationView), findsOneWidget);
        expect(find.text('Kasir — Buat Pesanan'), findsOneWidget);

        // 3. Switch to Antrean
        await tester.tap(find.text('Antrean'));
        await tester.pumpAndSettle();
        expect(find.text('Antrean Dapur'), findsOneWidget);

        // 4. Switch to Menu directly
        await tester.tap(find.text('Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Kelola Ketersediaan Menu'), findsOneWidget);

        // 5. Switch to Pengaturan directly
        await tester.tap(find.text('Pengaturan'));
        await tester.pumpAndSettle();
        expect(find.text('Pengaturan Outlet'), findsOneWidget);

        // 6. Open Design System Catalog from Settings
        await tester.tap(find.text('Buka Katalog Design System'));
        await tester.pumpAndSettle();
        expect(find.byType(DesignSystemShowcase), findsOneWidget);
      },
    );
  });
}
