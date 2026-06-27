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

    test('FoodEntry json round-trip incl. fibre + micros', () {
      const e = FoodEntry(id: '1', dateKey: '2026-06-24', name: 'Oats', calories: 300,
          fibre: 8, micros: {'iron_mg': 2.5, 'magnesium_mg': 60});
      final back = FoodEntry.fromJson(e.toJson());
      expect(back.name, 'Oats');
      expect(back.fibre, 8);
      expect(back.micros['iron_mg'], 2.5);
      expect(back.micros['magnesium_mg'], 60);
    });

    test('dietTotals sums micros per key across the day', () {
      const day = [
        FoodEntry(id: '1', dateKey: 'd', name: 'a', micros: {'iron_mg': 2, 'zinc_mg': 1}),
        FoodEntry(id: '2', dateKey: 'd', name: 'b', micros: {'iron_mg': 3}),
      ];
      final t = dietTotals(day, 'd');
      expect(t.micros['iron_mg'], 5); // 2 + 3
      expect(t.micros['zinc_mg'], 1);
    });

    test('totals sum fibre; macro kcal split', () {
      const day = [
        FoodEntry(id: '1', dateKey: 'd', name: 'a', protein: 30, carbs: 40, fat: 10, fibre: 5),
        FoodEntry(id: '2', dateKey: 'd', name: 'b', fibre: 3),
      ];
      final t = dietTotals(day, 'd');
      expect(t.fibre, 8);
      expect(t.proteinKcal, 120); // 30g × 4
      expect(t.fatKcal, 90); // 10g × 9
    });

    test('FoodEntry.fromGoogle maps a nutrition-log dict + round-trips', () {
      final g = FoodEntry.fromGoogle({
        'google_id': '7534057579911318776', 'name': 'Chicken Thigh, Fried',
        'day': '2026-06-27', 'calories': 144, 'protein': 11.2, 'carbs': 4.7,
        'fat': 8.6, 'fibre': 0.16,
      });
      expect(g.id, 'g:7534057579911318776');
      expect(g.fromGoogle, true);
      expect(g.name, 'Chicken Thigh, Fried');
      expect(g.calories, 144);
      expect(g.protein, 11.2);
      final back = FoodEntry.fromJson(g.toJson());
      expect(back.source, 'google');
      expect(back.googleId, '7534057579911318776');
      expect(back.calories, 144);
    });

    test('dietHealthScore averages the six axes (capped)', () {
      const e = FoodEntry(id: '1', dateKey: 'd', name: 'x',
          health: {'micronutrients': 60, 'fibre': 60, 'gut_health': 60,
            'antioxidants': 60, 'healthy_fats': 60, 'whole_food': 60});
      expect(dietTotals([e], 'd').healthScore, closeTo(60, 1e-9));
      // points accumulate + cap at 100 per axis
      final two = dietTotals([e, e], 'd');
      expect(two.health['fibre'], 100); // 60+60 capped
    });

    test('caloriesLastNDays returns the day-by-day trend ending today', () {
      const day = [
        FoodEntry(id: '1', dateKey: '2026-06-24', name: 'a', calories: 500),
        FoodEntry(id: '2', dateKey: '2026-06-24', name: 'b', calories: 200),
      ];
      final trend = caloriesLastNDays(day, n: 3, today: DateTime(2026, 6, 24));
      expect(trend.length, 3);
      expect(trend.last, 700); // today
      expect(trend.first, 0); // two days ago, nothing
    });
  });

  group('workout', () {
    const session = WorkoutSession(id: 's1', type: 'Weightlifting', start: '2026-06-24T18:00:00', sets: [
      WorkoutSet(name: 'Bench Press', mode: SetMode.weightReps, weight: 100, reps: 5),
      WorkoutSet(name: 'Bench Press', mode: SetMode.weightReps, weight: 110, reps: 3),
      WorkoutSet(name: 'Bicep Curl', mode: SetMode.weightReps, weight: 10, reps: 12),
      WorkoutSet(name: 'Run', mode: SetMode.time, seconds: 600),
    ]);

    test('volume sums weight×reps; non-weight modes contribute 0', () {
      expect(session.volume, 100 * 5 + 110 * 3 + 10 * 12); // 950 (run = 0)
    });

    test('exercises are the distinct set names', () {
      expect(session.exercises, {'Bench Press', 'Bicep Curl', 'Run'});
    });

    test('dateKey derives from the start datetime', () {
      expect(session.dateKey, '2026-06-24');
    });

    test('set detail formats per mode', () {
      expect(const WorkoutSet(name: 'x', mode: SetMode.weightReps, weight: 100, reps: 5).detail, '100 kg × 5');
      expect(const WorkoutSet(name: 'x', mode: SetMode.reps, reps: 12).detail, '12 reps');
      expect(const WorkoutSet(name: 'x', mode: SetMode.distance, distance: 5).detail, '5 km');
    });

    test('rollups over the last 7 days', () {
      final today = DateTime(2026, 6, 24);
      const old = WorkoutSession(id: 's0', type: 'Run', start: '2026-01-01T08:00:00',
          sets: [WorkoutSet(name: 'Squat', mode: SetMode.weightReps, weight: 100, reps: 5)]);
      final all = [session, old];
      expect(volumeOverDays(all, today: today), session.volume);
      expect(sessionsOverDays(all, today: today), 1);
      expect(exercisesOverDays(all, today: today), {'Bench Press', 'Bicep Curl', 'Run'});
    });

    test('volumePerDay bins by day, oldest→newest, zero-fills gaps', () {
      final today = DateTime(2026, 6, 24);
      const earlier = WorkoutSession(id: 's2', type: 'Weightlifting', start: '2026-06-22T10:00:00',
          sets: [WorkoutSet(name: 'Squat', mode: SetMode.weightReps, weight: 100, reps: 5)]);
      final series = volumePerDay([session, earlier], days: 3, today: today);
      expect(series, [500.0, 0.0, 950.0]); // 22nd, 23rd (gap), 24th
    });

    test('groupByExercise groups sets under each name in order', () {
      final g = groupByExercise(session.sets);
      expect(g.keys.toList(), ['Bench Press', 'Bicep Curl', 'Run']);
      expect(g['Bench Press']!.length, 2);
    });

    test('json round-trip incl. type + set modes', () {
      final back = WorkoutSession.fromJson(session.toJson());
      expect(back.type, 'Weightlifting');
      expect(back.sets.length, 4);
      expect(back.volume, session.volume);
      expect(back.sets[3].mode, SetMode.time);
    });

    test('fromGoogle builds a sourced session with cardio summary', () {
      final g = WorkoutSession.fromGoogle({
        'google_id': 'abc', 'type': 'Walk', 'display_name': 'Walk',
        'start': '2026-06-23T13:43:41', 'duration_mins': 37, 'cardio_load': 42,
        'calories': 229, 'distance_km': 1.64, 'steps': 2148, 'avg_hr': 73, 'zone_minutes': 2,
      });
      expect(g.id, 'g:abc');
      expect(g.fromGoogle, true);
      expect(g.type, 'Walk');
      expect(g.durationMins, 37);
      expect(g.cardioLoad, 42); // Edwards TRIMP, not calories
      expect(g.zoneMinutes, 2);
      expect(g.summary['calories'], 229);
      expect(g.summary['distance_km'], 1.64);
      // survives a json round-trip
      final back = WorkoutSession.fromJson(g.toJson());
      expect(back.source, 'google');
      expect(back.googleId, 'abc');
      expect(back.summary['avg_hr'], 73);
    });

    test('legacy json (day + e/w/r) still parses', () {
      final back = WorkoutSession.fromJson({
        'id': 'old', 'day': '2026-06-20',
        'sets': [{'e': 'bench', 'w': 100, 'r': 5}]
      });
      expect(back.dateKey, '2026-06-20');
      expect(back.sets.single.name, 'bench');
      expect(back.volume, 500); // mode defaults to weightReps
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

    test('save/load/delete workouts (upsert by id); clear wipes both', () {
      final r = InMemoryRepository();
      r.saveWorkout(const WorkoutSession(id: 'w', type: 'Weightlifting', start: '2026-06-24T10:00:00',
          sets: [WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 100, reps: 5)]));
      r.saveFood(const FoodEntry(id: 'a', dateKey: '2026-06-24', name: 'X'));
      expect(r.loadWorkouts().length, 1);
      // Saving the same id again upserts (edits), not duplicates.
      r.saveWorkout(const WorkoutSession(id: 'w', type: 'Run', start: '2026-06-24T10:00:00'));
      expect(r.loadWorkouts().length, 1);
      expect(r.loadWorkouts().single.type, 'Run');
      r.clear();
      expect(r.loadWorkouts(), isEmpty);
      expect(r.loadFood(), isEmpty);
    });
  });
}
