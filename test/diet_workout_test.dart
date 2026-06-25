// Diet + exercise (workout) data: totals, volume, best-set selection, rollups,
// json round-trips, and repository persistence.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/diet.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/workout.dart';

void main() {
  group('diet', () {
    const entries = [
      FoodEntry(id: '1', dateKey: '2026-06-24', name: 'Eggs', calories: 200, protein: 18),
      FoodEntry(id: '2', dateKey: '2026-06-24', name: 'Rice', calories: 300, carbs: 65),
      FoodEntry(id: '3', dateKey: '2026-06-23', name: 'Old', calories: 999),
    ];

    test('dietTotals sums only the given day', () {
      final t = dietTotals(entries, '2026-06-24');
      expect(t.calories, 500);
      expect(t.protein, 18);
      expect(t.carbs, 65);
      expect(t.items, 2);
    });

    test('entriesFor filters by day', () {
      expect(entriesFor(entries, '2026-06-23').single.name, 'Old');
    });

    test('FoodEntry json round-trip', () {
      final back = FoodEntry.fromJson(entries[0].toJson());
      expect(back.name, 'Eggs');
      expect(back.calories, 200);
      expect(back.protein, 18);
    });
  });

  group('workout', () {
    const session = WorkoutSession(id: 's1', dateKey: '2026-06-24', sets: [
      WorkoutSet('bench', 100, 5),
      WorkoutSet('bench', 110, 3),
      WorkoutSet('curl', 10, 12),
      WorkoutSet('curl', 12, 12),
    ]);

    test('volume sums weight×reps across sets', () {
      expect(session.volume, 100 * 5 + 110 * 3 + 10 * 12 + 12 * 12); // 1094
    });

    test('exercises set is distinct', () {
      expect(session.exercises, {'bench', 'curl'});
    });

    test('bestSets picks the heaviest 1RM (bench) and biggest volume (curl)', () {
      final best = bestSets(session);
      expect(best['bench']!.weight, 110); // higher est-1RM than 100×5
      expect(best['curl']!.weight, 12); // 12×12 rep-volume > 10×12
    });

    test('rollups over the last 7 days', () {
      final today = DateTime(2026, 6, 24);
      const old = WorkoutSession(id: 's0', dateKey: '2026-01-01', sets: [WorkoutSet('squat', 100, 5)]);
      final all = [session, old];
      expect(volumeOverDays(all, today: today), session.volume); // old one excluded
      expect(sessionsOverDays(all, today: today), 1);
      expect(exercisesOverDays(all, today: today), {'bench', 'curl'});
    });

    test('WorkoutSession json round-trip', () {
      final back = WorkoutSession.fromJson(session.toJson());
      expect(back.sets.length, 4);
      expect(back.volume, session.volume);
    });
  });

  group('repository diet + workout', () {
    test('save/load/delete food', () {
      final r = InMemoryRepository();
      r.saveFood(const FoodEntry(id: 'a', dateKey: '2026-06-24', name: 'X', calories: 100));
      expect(r.loadFood().length, 1);
      r.deleteFood('a');
      expect(r.loadFood(), isEmpty);
    });

    test('save/load/delete workouts; clear wipes both', () {
      final r = InMemoryRepository();
      r.saveWorkout(const WorkoutSession(id: 'w', dateKey: '2026-06-24', sets: [WorkoutSet('bench', 100, 5)]));
      r.saveFood(const FoodEntry(id: 'a', dateKey: '2026-06-24', name: 'X'));
      expect(r.loadWorkouts().length, 1);
      r.clear();
      expect(r.loadWorkouts(), isEmpty);
      expect(r.loadFood(), isEmpty);
    });
  });
}
