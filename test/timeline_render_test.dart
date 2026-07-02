import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/state/providers.dart';
import 'package:physical/ui/habits_screen.dart';

void main() {
  testWidgets('day timeline renders calendar-style', (tester) async {
    tester.view.physicalSize = const Size(440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    final t = todayKey();
    repo.saveHabit(Habit(id: 'a', title: 'Train', section: 'exercise', verify: 'manual',
        time: '07:30', durationMins: 60, createdAt: t));
    repo.saveHabit(Habit(id: 'b', title: 'Protein lunch', section: 'diet', verify: 'manual',
        time: '13:00', durationMins: 30, createdAt: t));
    repo.saveHabit(Habit(id: 'c', title: 'Skincare PM', section: 'aesthetics', verify: 'manual',
        time: '21:00', durationMins: 15, createdAt: t));
    repo.saveHabit(Habit(id: 'd', title: 'Read', section: 'misc', verify: 'manual', createdAt: t));
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: HabitsTab())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TIMELINE'), findsOneWidget);
  });
}
