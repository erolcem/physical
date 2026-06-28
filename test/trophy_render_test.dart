import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/providers.dart';
import 'package:physical/ui/home_screen.dart';

void main() {
  testWidgets('trophy room renders under total logs', (tester) async {
    tester.view.physicalSize = const Size(440, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    // a few ranked metrics so overall computes, + an overall_rank history
    repo.saveLog('vo2max', Log('vo2max', 52, ts: '2026-06-20T10:00:00'));
    for (final (d, v) in [('2026-01-01', 1.2), ('2026-02-01', 1.7), ('2026-03-01', 2.4),
                          ('2026-04-01', 3.6), ('2026-06-01', 4.2)]) {
      repo.saveLog('overall_rank', Log('overall_rank', v, ts: '${d}T12:00:00'));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Builder(builder: (ctx) => Scaffold(
        body: Center(child: ElevatedButton(
            onPressed: () => openOverallBreakdown(ctx), child: const Text('open'))),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TROPHY ROOM'), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
  });
}
