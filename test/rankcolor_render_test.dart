import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/rank_history.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/providers.dart';
import 'package:physical/ui/progress_screen.dart';

void main() {
  testWidgets('strength rank series renders tier-coloured', (tester) async {
    tester.view.physicalSize = const Size(460, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    for (var i = 0; i < 8; i++) {
      final d = '2026-06-${(10 + i).toString().padLeft(2, '0')}';
      repo.saveLog('bench', Log('bench', 70 + i * 8.0, bodyweight: 80, ts: '${d}T10:00:00'));
      repo.saveLog('squat', Log('squat', 100 + i * 9.0, bodyweight: 80, ts: '${d}T10:00:00'));
    }
    backfillRankLogs(repo);
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
          home: CategoryGraphPage(categoryId: 'strength', title: 'Strength')),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Strength Rank'), findsWidgets);
    // Subtitle renders the tier name (rank series shown in ranked-metric format).
    expect(find.textContaining(RegExp(r'rank \d')), findsOneWidget);
  });
}
