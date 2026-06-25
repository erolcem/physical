// Smoke tests — verify the app boots and every tab builds without throwing at
// runtime (the analyzer can't catch render-time errors).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/main.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PhysicalApp()));
    expect(find.text('Physical'), findsOneWidget);
  });

  testWidgets('every tab builds without runtime errors', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PhysicalApp()));
    await tester.pumpAndSettle();

    for (final label in ['Progress', 'Habits', 'Profile', 'Dashboard']) {
      await tester.tap(find.widgetWithText(Tab, label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label tab threw on build');
    }
  });
}
