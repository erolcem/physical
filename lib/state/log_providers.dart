// state/log_providers.dart — Riverpod wiring for diet (food) and exercise
// (workout) logging. Saving a workout also updates each exercise's rank from its
// best set, so the "big" data types feed straight into the ranks and the AI.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/correlation.dart';
import '../data/diet.dart';
import '../data/habits.dart' show todayKey;
import '../data/repository.dart';
import '../data/workout.dart';
import '../engine/rank_engine.dart' show Log, strengthValue;
import 'providers.dart';

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
    ));
    state = repo.loadFood();
  }

  void remove(String id) {
    repo.deleteFood(id);
    state = repo.loadFood();
  }
}

final workoutProvider =
    StateNotifierProvider<WorkoutNotifier, List<WorkoutSession>>((ref) {
  return WorkoutNotifier(ref);
});

class WorkoutNotifier extends StateNotifier<List<WorkoutSession>> {
  final Ref ref;
  late final Repository repo;
  WorkoutNotifier(this.ref) : super(const []) {
    repo = ref.read(repositoryProvider);
    state = repo.loadWorkouts();
  }

  /// Save a session and update each exercise's rank from its best set (1RM for
  /// compounds, rep-volume for isolations). Bodyweight defaults to the latest.
  void add(List<WorkoutSet> sets, {double? bodyweight}) {
    if (sets.isEmpty) return;
    final session = WorkoutSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      dateKey: todayKey(),
      sets: sets,
    );
    repo.saveWorkout(session);
    final bw = bodyweight ?? ref.read(currentBodyweightProvider);
    final logs = ref.read(logsProvider.notifier);
    for (final s in bestSets(session).values) {
      logs.add(
        s.exerciseId,
        Log(s.exerciseId, strengthValue(s.exerciseId, s.weight, s.reps),
            bodyweight: bw, ts: DateTime.now().toIso8601String()),
      );
    }
    state = repo.loadWorkouts();
  }

  void remove(String id) {
    repo.deleteWorkout(id);
    state = repo.loadWorkouts();
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
