import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/diet.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/providers.dart';
import 'package:physical/ui/habits_screen.dart';

void main() {
  testWidgets('habits tab shows target progress + verified', (tester) async {
    tester.view.physicalSize = const Size(440, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    final today = todayKey();
    repo.saveHabit(Habit(id: 'h1', title: 'Sleep score', section: 'sleep', verify: 'metric',
        linkedMetricId: 'sleep_score', target: 80, unit: '/100', createdAt: today));
    repo.saveHabit(Habit(id: 'h2', title: 'Protein', section: 'diet', verify: 'diet',
        goalKey: 'protein', target: 150, unit: 'g', createdAt: today));
    repo.saveHabit(Habit(id: 'h3', title: 'Skincare (PM)', section: 'aesthetics', verify: 'manual',
        createdAt: today));
    repo.saveLog('sleep_score', Log('sleep_score', 84, ts: '${today}T08:00:00')); // meets ≥80
    repo.saveFood(FoodEntry(id: 'f1', dateKey: today, name: 'meal', calories: 700, protein: 120)); // 120<150
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: HabitsTab())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('verified'), findsWidgets); // sleep auto-verified
  });
}
