import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/main.dart';

void main() {
  testWidgets('sleep screen opens without layout crash', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: PhysicalApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('LAST NIGHT'), findsOneWidget);
  });

  testWidgets('strength graph (All) renders without crash', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: PhysicalApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Strength'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
