import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/state/providers.dart';
import 'package:physical/ui/metric_detail_sheet.dart';
import 'package:physical/ui/hearing_test.dart';

void main() {
  testWidgets('ear detail sheet shows measure button + guide', (tester) async {
    tester.view.physicalSize = const Size(440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Builder(builder: (ctx) => Scaffold(
        body: Center(child: ElevatedButton(
            onPressed: () => openDetailSheet(ctx, 'ear'), child: const Text('open'))),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('👂  Measure hearing'), findsOneWidget);
    expect(find.textContaining('Hearing acuity'), findsOneWidget);
  });

  testWidgets('hearing sheet intro builds', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Consumer(builder: (ctx, ref, _) => Scaffold(
        body: Center(child: ElevatedButton(
            onPressed: () => measureHearingFlow(ctx, ref), child: const Text('go'))),
      ))),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Hearing test'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });
}
