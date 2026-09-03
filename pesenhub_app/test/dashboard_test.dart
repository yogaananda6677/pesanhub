import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/dashboard/dashboard_view.dart';
import 'package:pesenhub_app/dashboard/models/dashboard_state.dart';
import 'package:pesenhub_app/dashboard/models/operational_summary.dart';
import 'package:pesenhub_app/dashboard/widgets/metric_card.dart';
import 'package:pesenhub_app/shell/app_shell.dart';
import 'package:pesenhub_app/theme/app_theme.dart';
import 'package:pesenhub_app/widgets/app_feedback.dart';

void main() {
  group('Issue #25: Cashier Dashboard & Operational Summary Tests', () {
    final fixedTime = DateTime(2026, 9, 3, 14, 30);

    testWidgets(
      'Criteria #1: Metric cards display snapshot counts consistently',
      (tester) async {
        final summary = OperationalSummary(
          pendingCount: 5,
          preparingCount: 4,
          readyCount: 3,
          overdueCount: 2,
          completedCount: 25,
          pendingSyncCount: 1,
          lastUpdatedAt: fixedTime,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardView(state: DashboardState.success(summary)),
            ),
          ),
        );

        // Verify metric card titles and counts
        expect(find.text('5'), findsOneWidget);
        expect(find.text('Menunggu Konfirmasi'), findsOneWidget);

        expect(find.text('4'), findsOneWidget);
        expect(find.text('Sedang Dimasak'), findsOneWidget);

        expect(find.text('3'), findsOneWidget);
        expect(find.text('Siap Diambil'), findsOneWidget);

        expect(find.text('2'), findsOneWidget);
        expect(find.text('Pesanan Terlambat'), findsOneWidget);

        expect(find.text('25'), findsOneWidget);
        expect(find.text('Selesai Hari Ini'), findsOneWidget);

        expect(find.text('1'), findsOneWidget);
        expect(find.text('Antrean Offline'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #2: Last updated time and stale/offline warnings are displayed',
      (tester) async {
        // 1. Fresh state
        final freshSummary = OperationalSummary(
          pendingCount: 1,
          lastUpdatedAt: fixedTime,
          isStale: false,
          isOffline: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardView(state: DashboardState.success(freshSummary)),
            ),
          ),
        );

        expect(find.text('Terakhir diperbarui: 14:30'), findsOneWidget);
        expect(find.byType(AppBanner), findsNothing);

        // 2. Stale state
        final staleSummary = freshSummary.copyWith(isStale: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardView(state: DashboardState.success(staleSummary)),
            ),
          ),
        );

        expect(find.textContaining('Data Usang:'), findsOneWidget);

        // 3. Offline state
        final offlineSummary = freshSummary.copyWith(isOffline: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardView(
                state: DashboardState.success(offlineSummary),
              ),
            ),
          ),
        );

        expect(find.textContaining('Mode Offline:'), findsOneWidget);
        expect(find.text('Offline • Terakhir: 14:30'), findsOneWidget);
      },
    );

    testWidgets(
      'Criteria #3: 1-Tap navigation to POS, Queue, and KDS works from dashboard',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const AppShell()),
        );

        // Start on Ringkasan (Dashboard)
        expect(find.text('Ringkasan Operasional'), findsOneWidget);

        // 1-Tap to POS: tap 'Buat Pesanan Baru' button
        await tester.tap(find.text('Buat Pesanan Baru').first);
        await tester.pumpAndSettle();
        expect(find.text('Kasir — Buat Pesanan'), findsOneWidget);

        // Return to Ringkasan tab
        await tester.tap(find.text('Ringkasan'));
        await tester.pumpAndSettle();
        expect(find.text('Ringkasan Operasional'), findsOneWidget);

        // 1-Tap to KDS: tap 'Lihat Dapur KDS' button
        await tester.tap(find.text('Lihat Dapur KDS'));
        await tester.pumpAndSettle();
        expect(find.text('Dapur KDS — Tiket Memasak'), findsOneWidget);

        // Return to Ringkasan tab
        await tester.tap(find.text('Ringkasan'));
        await tester.pumpAndSettle();
        expect(find.text('Ringkasan Operasional'), findsOneWidget);

        // 1-Tap to Queue: tap 'Menunggu Konfirmasi' metric card
        await tester.tap(find.text('Menunggu Konfirmasi'));
        await tester.pumpAndSettle();
        expect(find.text('Antrean Pesanan'), findsOneWidget);
      },
    );

    testWidgets('Criteria #4: Loading state displays AppLoadingState', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: DashboardView(state: DashboardState.loading()),
          ),
        ),
      );

      expect(find.byType(AppLoadingState), findsOneWidget);
      expect(
        find.text('Memuat ringkasan operasional kasir...'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Criteria #4: Empty state displays AppEmptyState with action button',
      (tester) async {
        bool actionTriggered = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardView(
                state: const DashboardState.empty(),
                onNavigateToPos: () => actionTriggered = true,
              ),
            ),
          ),
        );

        expect(find.byType(AppEmptyState), findsOneWidget);
        expect(find.text('Tidak Ada Pesanan Aktif'), findsOneWidget);

        await tester.tap(find.text('Buat Pesanan Baru'));
        await tester.pump();
        expect(actionTriggered, isTrue);
      },
    );

    testWidgets(
      'Criteria #4: Error state displays AppErrorState and retry works',
      (tester) async {
        bool retried = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardView(
                state: const DashboardState.error(
                  'Koneksi timeout ke server lokal',
                ),
                onRefresh: () => retried = true,
              ),
            ),
          ),
        );

        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.text('Koneksi timeout ke server lokal'), findsOneWidget);

        await tester.tap(find.text('Coba Lagi'));
        await tester.pump();
        expect(retried, isTrue);
      },
    );

    testWidgets(
      'Criteria #4: Responsive layout on mobile and tablet without overflow',
      (tester) async {
        final summary = OperationalSummary(
          pendingCount: 3,
          preparingCount: 2,
          readyCount: 1,
          overdueCount: 1,
          completedCount: 10,
          pendingSyncCount: 2,
          lastUpdatedAt: fixedTime,
        );

        // Mobile viewport
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardView(state: DashboardState.success(summary)),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(MetricCard), findsNWidgets(6));

        // Tablet viewport
        tester.view.physicalSize = const Size(1024, 768);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(MetricCard), findsNWidgets(6));
      },
    );
  });
}
