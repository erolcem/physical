import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/providers.dart';
import 'package:physical/ui/body_graph.dart';
import 'package:physical/data/body_figure_data.dart';

void main() {
  testWidgets('back figure render', (tester) async {
    tester.view.physicalSize = const Size(300, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    for (final id in ['pullup', 'rdl', 'squat', 'hip_thrust']) {
      repo.saveLog(id, Log(id, 140, bodyweight: 80, ts: '2026-06-20T10:00:00'));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Scaffold(
        backgroundColor: const Color(0xFF08091A),
        body: Center(child: SizedBox(width: 150,
          child: BodyGraph(regions: backRegions, onTapMetric: (_) {}))),
      )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
