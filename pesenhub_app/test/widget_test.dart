import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/main.dart';

void main() {
  testWidgets('PesenHubApp blocks runtime without backend configuration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PesenHubApp());

    expect(find.textContaining('Backend belum dikonfigurasi'), findsOneWidget);
  });
}
