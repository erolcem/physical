import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/workout.dart';
import 'package:physical/data/diet.dart';
import 'package:physical/state/providers.dart';
import 'package:physical/ui/exercise_screen.dart';
import 'package:physical/ui/diet_screen.dart';

void main() {
  testWidgets('exercise graph uses GraphArea format with All', (tester) async {
    tester.view.physicalSize = const Size(440, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    for (var i = 0; i < 15; i++) {
      final d = DateTime(2026, 6, 28).subtract(Duration(days: i));
      final ds = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      repo.saveWorkout(WorkoutSession(id: 'w$i', type: 'run', title: 'Run',
          start: '${ds}T08:00:00', durationMins: 30, cardioLoad: 40 + i.toDouble(),
          summary: {'calories': 300.0}));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ExerciseScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('All'), findsWidgets); // the timeframe the others have
    expect(find.text('Cardio load'), findsWidgets);
  });

  testWidgets('diet graph uses GraphArea format with All', (tester) async {
    tester.view.physicalSize = const Size(440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    for (var i = 0; i < 12; i++) {
      final d = DateTime(2026, 6, 28).subtract(Duration(days: i));
      final ds = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      repo.saveFood(FoodEntry(id: 'f$i', dateKey: ds, name: 'Meal', calories: 600 + i * 10.0,
          protein: 40, carbs: 60, fat: 20, fibre: 8, health: const {'micronutrients': 30}));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: DietScreen()),
    ));
    await tester.pumpAndSettle();
    // The diet graph sits at the bottom of a lazy ListView — scroll it into view.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('All'), findsWidgets);
  });
}
