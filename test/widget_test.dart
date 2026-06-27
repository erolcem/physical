// Smoke tests — verify the app boots and every tab builds without throwing at
// runtime (the analyzer can't catch render-time errors).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:physical/main.dart';

void main() {
  // The api client reads a persisted token via shared_preferences; mock it empty
  // so the (signed-out) Coach tab resolves without any network.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PhysicalApp()));
    // Header is now the brand banner image; tabs confirm the shell built.
    expect(find.image(const AssetImage('assets/brand/header.png')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('overall breakdown sheet builds without errors', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PhysicalApp()));
    await tester.pump(const Duration(milliseconds: 300));
    // Tap the overall rank card → opens the category-breakdown sheet.
    await tester.tap(find.text('OVERALL RANK'));
    await tester.pump(); // start the sheet route
    await tester.pump(const Duration(milliseconds: 400)); // let it build (not settle: badge shimmer loops)
    expect(find.text('CATEGORY RANKINGS'), findsOneWidget);
    expect(find.text('RANK DISTRIBUTION'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tab builds without runtime errors', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PhysicalApp()));
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in ['Progress', 'Habits', 'Coach', 'Home']) {
      await tester.tap(find.widgetWithText(Tab, label));
      await tester.pump(); // start the tab transition
      await tester.pump(const Duration(milliseconds: 400)); // let it settle
      expect(tester.takeException(), isNull, reason: '$label tab threw on build');
    }
  });
}
