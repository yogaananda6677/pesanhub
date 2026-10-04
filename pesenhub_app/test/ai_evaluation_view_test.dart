import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/settings/views/ai_evaluation_view.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  Widget buildTestApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const AiEvaluationView(),
    );
  }

  group('AiEvaluationView Widget Tests', () {
    testWidgets(
      'Renders header, hero banner, filters, and default evaluations',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        expect(find.text('Evaluasi & Training AI'), findsOneWidget);
        expect(find.text('Evaluasi & Dataset Pelatihan AI'), findsOneWidget);
        expect(find.byKey(const Key('filter-eval-ALL')), findsOneWidget);
        expect(find.byKey(const Key('filter-eval-UNREVIEWED')), findsOneWidget);
        expect(find.byKey(const Key('filter-eval-GOOD')), findsOneWidget);
        expect(find.byKey(const Key('filter-eval-BAD')), findsOneWidget);

        // Verify conversation turns are displayed
        expect(find.text('Yoga (+6281234567890)'), findsOneWidget);
        expect(find.text('Budi (+6285712345678)'), findsOneWidget);
        expect(find.text('Siti (+6281999888777)'), findsOneWidget);
        expect(
          find.text('halo saya mau order minta katalognya dong kak'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Filters evaluations using category chips', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap 'Akurat (👍)'
      await tester.tap(find.byKey(const Key('filter-eval-GOOD')));
      await tester.pumpAndSettle();

      expect(find.text('Yoga (+6281234567890)'), findsOneWidget);
      expect(find.text('Budi (+6285712345678)'), findsNothing);
      expect(find.text('Siti (+6281999888777)'), findsNothing);

      // Tap 'Belum Direview'
      await tester.tap(find.byKey(const Key('filter-eval-UNREVIEWED')));
      await tester.pumpAndSettle();

      expect(find.text('Yoga (+6281234567890)'), findsNothing);
      expect(find.text('Budi (+6285712345678)'), findsOneWidget);
      expect(find.text('Siti (+6281999888777)'), findsOneWidget);
    });

    testWidgets('Searches evaluations by customer text or reply', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'rapat kantor');
      await tester.pumpAndSettle();

      expect(find.text('Siti (+6281999888777)'), findsOneWidget);
      expect(find.text('Yoga (+6281234567890)'), findsNothing);
      expect(find.text('Budi (+6285712345678)'), findsNothing);
    });

    testWidgets('Performs quick rating (thumbs up) on an unrated turn', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final goodButton = find.byKey(const Key('rating-good-eval-2'));
      await tester.ensureVisible(goodButton);
      await tester.tap(goodButton);
      await tester.pumpAndSettle();

      // eval-2 now has '👍 Akurat' badge
      expect(find.text('👍 Akurat'), findsNWidgets(2));
    });

    testWidgets('Opens Beri Koreksi modal dialog and submits feedback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final correctButton = find.byKey(const Key('correct-eval-button-eval-2'));
      await tester.ensureVisible(correctButton);
      await tester.tap(correctButton);
      await tester.pumpAndSettle();

      expect(find.text('Koreksi & Jawaban Ideal AI'), findsOneWidget);
      expect(find.byKey(const Key('input-correction-notes')), findsOneWidget);
      expect(find.byKey(const Key('input-expected-reply')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('input-correction-notes')),
        'Harga red velvet sudah naik',
      );
      await tester.enterText(
        find.byKey(const Key('input-expected-reply')),
        'Tambahan red velvet adalah Rp 3.000 ya kak.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit-correction-button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Jawaban Ideal yang Seharusnya'),
        findsOneWidget,
      );
      expect(
        find.text('Tambahan red velvet adalah Rp 3.000 ya kak.'),
        findsOneWidget,
      );
    });

    testWidgets('Opens Dataset Training Exporter bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final exportButton = find.byKey(const Key('export-ai-dataset-button'));
      expect(exportButton, findsOneWidget);

      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Export Dataset AI'), findsOneWidget);
      expect(find.text('Salin Semua Dataset ke Clipboard'), findsOneWidget);
    });
  });
}
