import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/providers.dart';
import 'package:physical/ui/metric_detail_sheet.dart';

void main() {
  testWidgets('metric history with 50 logs windows without error', (tester) async {
    tester.view.physicalSize = const Size(440, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    for (var i = 0; i < 50; i++) {
      final d = DateTime(2026, 6, 28).subtract(Duration(days: i));
      final ds = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      repo.saveLog('resting_hr', Log('resting_hr', 55 + (i % 7).toDouble(), ts: '${ds}T08:00:00'));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Builder(builder: (ctx) => Scaffold(
        body: Center(child: ElevatedButton(
            onPressed: () => openDetailSheet(ctx, 'resting_hr'), child: const Text('open'))),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('HISTORY · 50'), findsOneWidget);
    // ListView present (the windowed scroll) — only some rows built, not all 50.
    expect(find.byType(ListView), findsWidgets);
  });
}
