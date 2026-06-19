// Basic smoke test — verifies the app boots without crashing.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/main.dart';

void main() {
  testWidgets('App boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PhysicalApp()),
    );
    expect(find.text('Physical'), findsOneWidget);
  });
}
