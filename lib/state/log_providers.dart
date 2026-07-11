// state/log_providers.dart — Riverpod wiring for diet (food) and exercise
// (workout session) logging. Workouts are a training/volume log decoupled from
// ranks (lifts are logged separately for ranking); both feed the coach + habits.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart' show ApiClient, InferredNutrition;
import '../data/correlation.dart';
import '../data/diet.dart';
import '../data/habits.dart' show todayKey;
import '../data/pins.dart';
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
    final now = DateTime.now();
    repo.saveFood(FoodEntry(
      id: now.microsecondsSinceEpoch.toString(),
      dateKey: todayKey(),
      name: name.trim(),
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fibre: fibre,
      micros: micros,
      health: health,
      // Eaten-at time (assumed "now" — you log as you eat). Meal-identity
      // habits (Breakfast/Dinner) verify against this.
      time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
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
//
// SETS EXIST ONLY INSIDE A GOOGLE-IMPORTED (WATCH) EXERCISE — the owner's rule.
// There is deliberately NO createSession/createFromTemplate: nothing in the UI
// can mint a standalone workout. Sessions enter this store two ways only:
// importGoogle (the watch exercises) and repoMerge (legacy holders riding an
// old backup, which relinkToWatch migrates into their covering exercise).
class WorkoutNotifier extends StateNotifier<List<WorkoutSession>> {
  final Repository repo;
  WorkoutNotifier(this.repo) : super(repo.loadWorkouts());

  /// The live session for [id], following the absorption trail: when a legacy
  /// holder has merged into its watch parent, the parent is the answer.
  WorkoutSession? resolve(String id) =>
      state.where((x) => x.id == id).firstOrNull ??
      state.where((x) => x.absorbedIds.contains(id)).firstOrNull;

  void updateSession(WorkoutSession s) {
    repo.saveWorkout(s);
    state = repo.loadWorkouts();
  }

  void addSet(String sessionId, WorkoutSet set) {
    final s = resolve(sessionId);
    if (s == null) return;
    repo.saveWorkout(s.copyWith(sets: [...s.sets, set]));
    relinkToWatch();
    state = repo.loadWorkouts();
  }

  /// Append a template's sets as CHILDREN of an existing session — including a
  /// Google-imported exercise. The sets live inside the real tracked exercise;
  /// no separate entity is created.
  void applyTemplateToSession(String sessionId, WorkoutTemplate t) {
    final s = resolve(sessionId);
    if (s == null) return;
    repo.saveWorkout(s.copyWith(sets: [...s.sets, ...t.blankSets]));
    relinkToWatch();
    state = repo.loadWorkouts();
  }

  /// Edit an existing set in place (Hevy-style: tap a set, change weight/reps).
  void updateSet(String sessionId, int index, WorkoutSet set) {
    final s = resolve(sessionId);
    if (s == null || index < 0 || index >= s.sets.length) return;
    final sets = [...s.sets]..[index] = set;
    repo.saveWorkout(s.copyWith(sets: sets));
    relinkToWatch();
    state = repo.loadWorkouts();
  }

  void removeSet(String sessionId, int index) {
    final s = resolve(sessionId);
    if (s == null || index < 0 || index >= s.sets.length) return;
    final sets = [...s.sets]..removeAt(index);
    repo.saveWorkout(s.copyWith(sets: sets));
    state = repo.loadWorkouts();
  }

  /// Locate [original] in the LIVE resolved session and find its index — by
  /// instance first, then by equal values. An index captured in the UI goes
  /// stale the moment the holder absorbs into its watch parent (the parent's
  /// existing sets shift every position), which used to corrupt a different
  /// set; resolving at apply time can never write to the wrong one.
  int _liveIndex(WorkoutSession s, WorkoutSet original) {
    final byRef = s.sets.indexWhere((x) => identical(x, original));
    if (byRef >= 0) return byRef;
    return s.sets.indexWhere((x) => x.sameValues(original));
  }

  /// Edit [original] wherever it lives NOW (safe across absorption). No-op if
  /// the set no longer exists — never falls back to a positional guess.
  void updateSetRef(String sessionId, WorkoutSet original, WorkoutSet edited) {
    final s = resolve(sessionId);
    if (s == null) return;
    final idx = _liveIndex(s, original);
    if (idx >= 0) updateSet(s.id, idx, edited);
  }

  /// Remove [original] wherever it lives NOW (safe across absorption).
  void removeSetRef(String sessionId, WorkoutSet original) {
    final s = resolve(sessionId);
    if (s == null) return;
    final idx = _liveIndex(s, original);
    if (idx >= 0) removeSet(s.id, idx);
  }

  void remove(String id) {
    repo.deleteWorkout(id);
    state = repo.loadWorkouts();
  }

  /// Import Google exercise sessions (dedup by googleId), returning how many were new.
  /// Existing imports keep any sets the user has logged into them. After import,
  /// manual set-logging sessions are auto-linked to the watch exercise that covers
  /// them (two-step verification: sets anchored to a REAL tracked exercise).
  int importGoogle(List<Map<String, dynamic>> sessions) {
    final have = {for (final s in state) if (s.googleId != null) s.googleId};
    var added = 0;
    for (final g in sessions) {
      final gid = g['google_id'];
      if (gid == null || have.contains(gid)) continue;
      repo.saveWorkout(WorkoutSession.fromGoogle(g));
      added++;
    }
    relinkToWatch();
    if (added > 0) state = repo.loadWorkouts();
    return added;
  }

  /// Re-run the manual-session ↔ watch-exercise linking, then ABSORB each linked
  /// manual session into its parent watch exercise: the sets become children of
  /// the real tracked exercise and the manual container disappears — one workout,
  /// one entry (also called on sync).
  void relinkToWatch() {
    final linked = linkSessionsToWatch(repo.loadWorkouts());
    for (final s in linked) {
      repo.saveWorkout(s);
    }
    final (parents, removeIds) = absorbLinkedSessions(repo.loadWorkouts());
    for (final p in parents) {
      repo.saveWorkout(p);
    }
    for (final id in removeIds) {
      repo.deleteWorkout(id);
    }
    if (linked.isNotEmpty || parents.isNotEmpty) state = repo.loadWorkouts();
  }
}

final templatesProvider =
    StateNotifierProvider<TemplatesNotifier, List<WorkoutTemplate>>((ref) {
  return TemplatesNotifier(ref.watch(repositoryProvider));
});

// Workout templates (Hevy-style): save a session's sets under a name; starting
// from a template pre-fills a new session so nothing is retyped.
class TemplatesNotifier extends StateNotifier<List<WorkoutTemplate>> {
  final Repository repo;
  TemplatesNotifier(this.repo) : super(repo.loadTemplates());

  void saveFromSession(WorkoutSession s, String name) {
    if (name.trim().isEmpty) return;
    repo.saveTemplate(WorkoutTemplate.fromSession(s, name: name.trim()));
    state = repo.loadTemplates();
  }

  /// Upsert a template directly (AI-planned workouts, future editors).
  void save(WorkoutTemplate t) {
    repo.saveTemplate(t);
    state = repo.loadTemplates();
  }

  void remove(String id) {
    repo.deleteTemplate(id);
    state = repo.loadTemplates();
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

// AI pins — standing goals/context for the coach (Habits tab pin section).
// Every coach request carries them; deleted manually when no longer true.
final aiPinsProvider =
    StateNotifierProvider<AiPinsNotifier, List<AiPin>>((ref) {
  return AiPinsNotifier(ref.watch(repositoryProvider));
});

class AiPinsNotifier extends StateNotifier<List<AiPin>> {
  final Repository repo;
  AiPinsNotifier(this.repo) : super(repo.loadAiPins());

  void add(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    // Same text pinned twice adds nothing for the coach — keep one.
    if (state.any((p) => p.text.toLowerCase() == t.toLowerCase())) return;
    repo.saveAiPin(AiPin(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: t,
        createdAt: DateTime.now().toIso8601String()));
    state = repo.loadAiPins();
  }

  void remove(String id) {
    repo.deleteAiPin(id);
    state = repo.loadAiPins();
  }

  void reload() => state = repo.loadAiPins();
}
