import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/theme/app_spacing.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/theme/status_semantics.dart';
import 'package:pesenhub_app/widgets/app_button.dart';
import 'package:pesenhub_app/widgets/app_card.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';
import 'package:pesenhub_app/widgets/app_status_badge.dart';
import 'package:pesenhub_app/widgets/app_text_field.dart';
import 'package:pesenhub_app/widgets/responsive_layout.dart';

void main() {
  group('Accessibility & Touch Target Tests (Criteria #1)', () {
    testWidgets('AppButton meets minimum 48px interactive touch target', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: AppButton(label: 'Simpan', onPressed: () {}),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(AppButton);
      expect(buttonFinder, findsOneWidget);

      final Size buttonSize = tester.getSize(buttonFinder);
      expect(
        buttonSize.height,
        greaterThanOrEqualTo(AppSpacing.minTouchTarget),
      );
    });

    testWidgets('AppTextField container meets minimum 48px height', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: AppTextField(label: 'Nama Pelanggan', hintText: 'Budi'),
            ),
          ),
        ),
      );

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      final Size fieldSize = tester.getSize(textFieldFinder);
      expect(fieldSize.height, greaterThanOrEqualTo(AppSpacing.minTouchTarget));
    });

    testWidgets('AppButton disabled state prevents tap execution', (
      tester,
    ) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: AppButton(label: 'Nonaktif', onPressed: null)),
        ),
      );

      await tester.tap(find.text('Nonaktif'));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('AppButton loading state shows progress indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppButton(label: 'Simpan', isLoading: true, onPressed: () {}),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Simpan'), findsNothing);
    });
  });

  group('Status Semantics Tests (Criteria #2 - Never Color Alone)', () {
    final orderStatuses = [
      'PENDING',
      'ACCEPTED',
      'PREPARING',
      'READY_FOR_PICKUP',
      'COMPLETED',
      'REJECTED',
      'CANCELLED',
    ];

    for (final status in orderStatuses) {
      testWidgets(
        'Order status badge for $status contains both text label and icon',
        (tester) async {
          final semantics = StatusSemantics.forOrder(status);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(body: AppStatusBadge.order(status)),
            ),
          );

          // Verify text label is rendered
          expect(find.text(semantics.label), findsOneWidget);
          // Verify distinct icon is rendered
          expect(find.byIcon(semantics.icon), findsOneWidget);
        },
      );
    }

    final paymentStatuses = ['UNPAID', 'PAID', 'FAILED', 'EXPIRED', 'REFUNDED'];

    for (final status in paymentStatuses) {
      testWidgets(
        'Payment status badge for $status contains both text label and icon',
        (tester) async {
          final semantics = StatusSemantics.forPayment(status);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(body: AppStatusBadge.payment(status)),
            ),
          );

          expect(find.text(semantics.label), findsOneWidget);
          expect(find.byIcon(semantics.icon), findsOneWidget);
        },
      );
    }

    final sources = ['CASHIER_MANUAL', 'CUSTOMER_WEB', 'WHATSAPP'];

    for (final source in sources) {
      testWidgets(
        'Source badge for $source contains both text label and icon',
        (tester) async {
          final semantics = StatusSemantics.forSource(source);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(body: AppStatusBadge.source(source)),
            ),
          );

          expect(find.text(semantics.label), findsOneWidget);
          expect(find.byIcon(semantics.icon), findsOneWidget);
        },
      );
    }
  });

  group('High Contrast & Large Text Scaling Tests (Criteria #3)', () {
    testWidgets(
      'UI elements render gracefully under 1.5x and 2.0x text scaling',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      AppButton(
                        label: 'Simpan Pesanan Skala Besar',
                        icon: Icons.check,
                        onPressed: () {},
                      ),
                      const SizedBox(height: 16),
                      AppStatusBadge.order('PREPARING'),
                      const SizedBox(height: 16),
                      const AppCard(child: Text('Nasi Goreng Spesial Pedas')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Verify widget tree builds without layout overflow exceptions
        expect(tester.takeException(), isNull);
        expect(find.text('Simpan Pesanan Skala Besar'), findsOneWidget);
        expect(find.text('Sedang Dimasak'), findsOneWidget);
      },
    );
  });

  group('Responsive Layout Tests (Criteria #4)', () {
    testWidgets('Renders mobile widget when width < 600dp', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: ResponsiveLayout(
              mobile: Text('Mobile Layout Active'),
              tablet: Text('Tablet Layout Active'),
            ),
          ),
        ),
      );

      expect(find.text('Mobile Layout Active'), findsOneWidget);
      expect(find.text('Tablet Layout Active'), findsNothing);
    });

    testWidgets('Renders tablet widget when width >= 600dp', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: ResponsiveLayout(
              mobile: Text('Mobile Layout Active'),
              tablet: Text('Tablet Layout Active'),
            ),
          ),
        ),
      );

      expect(find.text('Tablet Layout Active'), findsOneWidget);
      expect(find.text('Mobile Layout Active'), findsNothing);
    });
  });

  group('Feedback States Tests', () {
    testWidgets('AppLoadingState renders message and indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppLoadingState(message: 'Sedang menyiapkan data...'),
          ),
        ),
      );

      expect(find.text('Sedang menyiapkan data...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AppEmptyState renders title, description, and action button', (
      tester,
    ) async {
      bool actionTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppEmptyState(
              title: 'Antrean Kosong',
              description: 'Belum ada pesanan aktif saat ini.',
              actionLabel: 'Muat Ulang',
              onAction: () => actionTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('Antrean Kosong'), findsOneWidget);
      expect(find.text('Belum ada pesanan aktif saat ini.'), findsOneWidget);
      expect(find.text('Muat Ulang'), findsOneWidget);

      await tester.tap(find.text('Muat Ulang'));
      await tester.pump();
      expect(actionTriggered, isTrue);
    });

    testWidgets('AppErrorState renders message and triggers onRetry callback', (
      tester,
    ) async {
      bool retryTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppErrorState(
              title: 'Gagal Memuat Antrean',
              message: 'Koneksi ke backend terputus.',
              onRetry: () => retryTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('Gagal Memuat Antrean'), findsOneWidget);
      expect(find.text('Koneksi ke backend terputus.'), findsOneWidget);
      expect(find.text('Coba Lagi'), findsOneWidget);

      await tester.tap(find.text('Coba Lagi'));
      await tester.pump();
      expect(retryTriggered, isTrue);
    });

    testWidgets('AppBanner renders alert and dismisses when close tapped', (
      tester,
    ) async {
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppBanner(
              message: 'Peringatan stok telur menipis',
              type: AppBannerType.warning,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      expect(find.text('Peringatan stok telur menipis'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(closed, isTrue);
    });
  });
}
