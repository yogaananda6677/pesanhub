import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/main.dart';
import 'package:pesenhub_app/shell/app_shell.dart';

void main() {
  testWidgets('PesenHubApp smoke test and AppShell mounting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PesenHubApp());

    // Verify AppShell is mounted as home
    expect(find.byType(AppShell), findsOneWidget);

    // Verify header and cashier destination title
    expect(find.text('Kasir — Buat Pesanan'), findsOneWidget);
    expect(find.text('PesenHub Outlet #01 — Nasi Goreng'), findsOneWidget);
  });
}
