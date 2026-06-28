import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/workout.dart';
import 'package:physical/state/providers.dart';
import 'package:physical/ui/exercise_screen.dart';

void main() {
  testWidgets('exercise metric graph renders', (tester) async {
    tester.view.physicalSize = const Size(440, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    for (var i = 0; i < 20; i++) {
      final d = DateTime(2026, 6, 28).subtract(Duration(days: i));
      final ds = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      repo.saveWorkout(WorkoutSession(id: 'w$i', type: 'run', title: 'Run',
          start: '${ds}T08:00:00', durationMins: 30 + i, cardioLoad: 40 + i * 2.0,
          summary: {'calories': 300 + i * 10.0}));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ExerciseScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Cardio load'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
  });
}
