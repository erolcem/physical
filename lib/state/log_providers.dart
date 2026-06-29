// state/log_providers.dart — Riverpod wiring for diet (food) and exercise
// (workout session) logging. Workouts are a training/volume log decoupled from
// ranks (lifts are logged separately for ranking); both feed the coach + habits.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart' show ApiClient, InferredNutrition;
import '../data/correlation.dart';
import '../data/diet.dart';
import '../data/habits.dart' show todayKey;
import '../data/readiness.dart';
import '../data/repository.dart';
import '../data/workout.dart';
import 'providers.dart';

/// Daily Readiness (0–100) from recovery signals + recent training load. Null until
/// there's recovery data. Recomputes when logs or workouts change.
final dailyReadinessProvider = Provider<double?>((ref) {
  return dailyReadiness(ref.watch(logsProvider), ref.watch(workoutProvider));
});

final dietProvider =
    StateNotifierProvider<DietNotifier, List<FoodEntry>>((ref) {
  return DietNotifier(ref.watch(repositoryProvider));
});

class DietNotifier extends StateNotifier<List<FoodEntry>> {
  final Repository repo;
  DietNotifier(this.repo) : super(repo.loadFood());

  void add({
    required String name,
    double calories = 0,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    double fibre = 0,
    Map<String, double> micros = const {},
    Map<String, double> health = const {},
  }) {
    if (name.trim().isEmpty) return;
    repo.saveFood(FoodEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      dateKey: todayKey(),
      name: name.trim(),
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fibre: fibre,
      micros: micros,
      health: health,
    ));
    state = repo.loadFood();
  }

  void remove(String id) {
    repo.deleteFood(id);
    state = repo.loadFood();
  }

  /// Import Google Health food logs (dedup by googleId), returning how many were new.
  int importGoogle(List<Map<String, dynamic>> foods) {
    final have = {for (final f in state) if (f.googleId != null) f.googleId};
    var added = 0;
    for (final g in foods) {
      final gid = g['google_id'];
      if (gid == null || have.contains(gid)) continue;
      repo.saveFood(FoodEntry.fromGoogle(g));
      added++;
    }
    if (added > 0) state = repo.loadFood();
    return added;
  }

  /// Fill the diet-health radar for foods that have macros but no health axes (mainly
  /// Google-imported food) by asking the AI to infer health points from the food name.
  ///
  /// Fast + resilient: (1) DEDUPES by food name so the same item (e.g. "oatmeal" logged
  /// daily) is inferred ONCE and applied to every copy; (2) runs the AI calls in PARALLEL
  /// batches instead of one-at-a-time; (3) writes results + refreshes the radar after each
  /// batch so it fills PROGRESSIVELY rather than all-at-once at the end. Best-effort.
  Future<int> enrichFoodHealth(ApiClient api, {int maxNames = 40}) async {
    final pending = [for (final f in state) if (f.health.isEmpty && f.calories > 0) f]
      ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
    if (pending.isEmpty) return 0;
    final byName = <String, List<FoodEntry>>{};
    for (final f in pending) {
      (byName[f.name.trim().toLowerCase()] ??= []).add(f);
    }
    final names = byName.keys.take(maxNames).toList();
    var done = 0;
    const batch = 5; // parallel AI calls per round
    for (var i = 0; i < names.length; i += batch) {
      final end = i + batch > names.length ? names.length : i + batch;
      final results = await Future.wait([
        for (final name in names.sublist(i, end))
          api.inferNutrition(byName[name]!.first.name)
              .then<InferredNutrition?>((n) => n)
              .catchError((_) => null)
      ]);
      for (var k = i; k < end; k++) {
        final n = results[k - i];
        if (n == null || n.health.isEmpty) continue;
        for (final f in byName[names[k]]!) {
          repo.saveFood(f.copyWith(health: n.health, micros: f.micros.isEmpty ? n.micros : null));
          done++;
        }
      }
      if (mounted) state = repo.loadFood(); // progressive radar fill after each batch
    }
    return done;
  }
}

final workoutProvider =
    StateNotifierProvider<WorkoutNotifier, List<WorkoutSession>>((ref) {
  return WorkoutNotifier(ref.watch(repositoryProvider));
});

// Exercise sessions are a training/volume log (stats + coach + habits) — decoupled
// from ranks. Lifts are logged separately in their metric cards for ranking.
class WorkoutNotifier extends StateNotifier<List<WorkoutSession>> {
  final Repository repo;
  WorkoutNotifier(this.repo) : super(repo.loadWorkouts());

  /// Create a new session (a workout you then log sets into).
  WorkoutSession createSession({required String type, String? title, int? durationMins}) {
    final s = WorkoutSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type, title: title, durationMins: durationMins,
      start: DateTime.now().toIso8601String(),
    );
    repo.saveWorkout(s);
    state = repo.loadWorkouts();
    return s;
  }

  void updateSession(WorkoutSession s) {
    repo.saveWorkout(s);
    state = repo.loadWorkouts();
  }

  void addSet(String sessionId, WorkoutSet set) {
    final s = state.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return;
    repo.saveWorkout(s.copyWith(sets: [...s.sets, set]));
    state = repo.loadWorkouts();
  }

  void removeSet(String sessionId, int index) {
    final s = state.where((x) => x.id == sessionId).firstOrNull;
    if (s == null || index < 0 || index >= s.sets.length) return;
    final sets = [...s.sets]..removeAt(index);
    repo.saveWorkout(s.copyWith(sets: sets));
    state = repo.loadWorkouts();
  }

  void remove(String id) {
    repo.deleteWorkout(id);
    state = repo.loadWorkouts();
  }

  /// Import Google exercise sessions (dedup by googleId), returning how many were new.
  /// Existing imports keep any sets the user has logged into them.
  int importGoogle(List<Map<String, dynamic>> sessions) {
    final have = {for (final s in state) if (s.googleId != null) s.googleId};
    var added = 0;
    for (final g in sessions) {
      final gid = g['google_id'];
      if (gid == null || have.contains(gid)) continue;
      repo.saveWorkout(WorkoutSession.fromGoogle(g));
      added++;
    }
    if (added > 0) state = repo.loadWorkouts();
    return added;
  }
}

final pinsProvider =
    StateNotifierProvider<PinsNotifier, List<PinnedCorrelation>>((ref) {
  return PinsNotifier(ref.watch(repositoryProvider));
});

class PinsNotifier extends StateNotifier<List<PinnedCorrelation>> {
  final Repository repo;
  PinsNotifier(this.repo) : super(repo.loadPins());

  void add(String a, String b) {
    if (a == b) return;
    repo.addPin(PinnedCorrelation(a, b));
    state = repo.loadPins();
  }

  void remove(String key) {
    repo.removePin(key);
    state = repo.loadPins();
  }
}
