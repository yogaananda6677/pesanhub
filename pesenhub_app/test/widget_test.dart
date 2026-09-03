import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/main.dart';
import 'package:pesenhub_app/showcase/design_system_showcase.dart';

void main() {
  testWidgets('PesenHubApp smoke test and showcase verification', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PesenHubApp());

    // Verify title and design system showcase is mounted
    expect(find.text('PesenHub Design System'), findsOneWidget);
    expect(find.byType(DesignSystemShowcase), findsOneWidget);

    // Verify key sections are visible
    expect(find.text('Typography & Brand'), findsOneWidget);
    expect(find.text('Interactive Buttons (Min 48px Target)'), findsOneWidget);
  });
}
