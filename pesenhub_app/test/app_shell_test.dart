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

        // Mobile keeps only the four operational destinations plus Lainnya.
        for (final destination in AppDestination.values.take(4)) {
          expect(find.text(destination.label), findsOneWidget);
        }
        expect(find.text('Lainnya'), findsOneWidget);
        final navigationBar = tester.widget<NavigationBar>(
          find.byKey(const Key('primary-bottom-navigation')),
        );
        expect(navigationBar.destinations, hasLength(5));
        expect(
          find.descendant(
            of: find.byKey(const Key('primary-bottom-navigation')),
            matching: find.text('Menu'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('primary-bottom-navigation')),
            matching: find.text('Pengaturan'),
          ),
          findsNothing,
        );

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

        // Navigate to 'Dapur KDS' (index 3)
        await tester.tap(find.text('Dapur KDS'));
        await tester.pumpAndSettle();

        expect(find.text('Dapur KDS — Tiket Memasak'), findsOneWidget);
        expect(find.byType(KdsDestinationView), findsOneWidget);

        // Rotate device to landscape (800 x 400)
        tester.view.physicalSize = const Size(800, 400);
        await tester.pumpAndSettle();

        // Verify KDS destination remains active after rotation/resize
        expect(find.text('Dapur KDS — Tiket Memasak'), findsOneWidget);
        expect(find.byType(KdsDestinationView), findsOneWidget);
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

        // Enter customer name in POS view
        final nameField = find.widgetWithText(
          TextField,
          'Contoh: Budi Santoso',
        );
        expect(nameField, findsOneWidget);
        await tester.enterText(nameField, 'Pak Bambang Sukses');
        await tester.pump();

        expect(find.text('Pak Bambang Sukses'), findsOneWidget);

        // Expand to tablet size (900 x 700)
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
        expect(find.text('Antrean Pesanan'), findsOneWidget);

        // 4. Open secondary destinations, then switch to Menu.
        await tester.tap(find.text('Lainnya'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('more-destinations-sheet')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('more-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Kelola Ketersediaan Menu'), findsOneWidget);

        // 5. Open Lainnya again, then switch to Pengaturan.
        await tester.tap(find.text('Lainnya'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('more-settings')));
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
