import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/state/providers.dart';
import 'package:physical/ui/habits_screen.dart';

void main() {
  testWidgets('planner: budget card + 24h density render', (tester) async {
    tester.view.physicalSize = const Size(440, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    final t = todayKey();
    repo.saveHabit(Habit(id: 'h1', title: 'Skincare (PM)', section: 'aesthetics', verify: 'manual',
        time: '21:00', durationMins: 10, cost: 3, products: const ['CeraVe', 'SPF50'], createdAt: t));
    repo.saveHabit(Habit(id: 'h2', title: 'Train', section: 'exercise', verify: 'workout',
        time: '07:30', durationMins: 60, createdAt: t));
    repo.saveHabit(Habit(id: 'h3', title: 'Protein', section: 'diet', verify: 'diet',
        goalKey: 'protein', target: 150, unit: 'g', time: '13:00', createdAt: t));
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: HabitsTab())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TIME / MONTH'), findsOneWidget);
    expect(find.text('COST / MONTH'), findsOneWidget);
    expect(find.text('TIMELINE'), findsOneWidget);
    expect(find.textContaining('CeraVe'), findsOneWidget); // product pill
  });
}
