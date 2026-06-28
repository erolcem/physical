// data/repository.dart — the storage seam. Nothing in the UI touches storage
// directly; everything goes through Repository. InMemoryRepository is the
// fallback/default (and used in tests); PersistentRepository (shared_preferences)
// is wired in main.dart for real on-device storage. Same interface either way.
import '../engine/rank_engine.dart' show Log, strengthValue;
import 'correlation.dart';
import 'diet.dart';
import 'habits.dart';
import 'workout.dart';

abstract class Repository {
  Map<String, List<Log>> loadLogs();
  void saveLog(String metricId, Log log);
  void deleteLog(String metricId, int index);
  void clear();

  // Habits (Phase 2) — accountability layer, stored separately from logs.
  List<Habit> loadHabits();
  void saveHabit(Habit habit);
  void deleteHabit(String id);
  Map<String, Set<String>> loadCompletions(); // habitId → set of done date-keys
  void setCompletion(String habitId, String day, bool done);

  // Diet (PDF Part 1) — food log entries with macros.
  List<FoodEntry> loadFood();
  void saveFood(FoodEntry entry);
  void deleteFood(String id);

  // Exercise (PDF Part 1) — workout sessions (sets → volume + muscle groups).
  List<WorkoutSession> loadWorkouts();
  void saveWorkout(WorkoutSession session);
  void deleteWorkout(String id);

  // Strategic correlations (PDF Part 5) — pairs pinned to the dashboard.
  List<PinnedCorrelation> loadPins();
  void addPin(PinnedCorrelation pin);
  void removePin(String key);
}

class InMemoryRepository implements Repository {
  final Map<String, List<Log>> _logs = {};
  final List<Habit> _habits = [];
  final Map<String, Set<String>> _completions = {};
  final List<FoodEntry> _food = [];
  final List<WorkoutSession> _workouts = [];
  final List<PinnedCorrelation> _pins = [];

  @override
  Map<String, List<Log>> loadLogs() =>
      {for (final e in _logs.entries) e.key: List.of(e.value)};

  @override
  void saveLog(String metricId, Log log) => (_logs[metricId] ??= []).add(log);

  @override
  void deleteLog(String metricId, int index) {
    final list = _logs[metricId];
    if (list != null && index >= 0 && index < list.length) list.removeAt(index);
  }

  @override
  List<Habit> loadHabits() => List.of(_habits);

  @override
  void saveHabit(Habit habit) {
    final i = _habits.indexWhere((h) => h.id == habit.id);
    if (i >= 0) {
      _habits[i] = habit;
    } else {
      _habits.add(habit);
    }
  }

  @override
  void deleteHabit(String id) {
    _habits.removeWhere((h) => h.id == id);
    _completions.remove(id);
  }

  @override
  Map<String, Set<String>> loadCompletions() =>
      {for (final e in _completions.entries) e.key: Set.of(e.value)};

  @override
  void setCompletion(String habitId, String day, bool done) {
    final set = _completions[habitId] ??= <String>{};
    done ? set.add(day) : set.remove(day);
  }

  @override
  List<FoodEntry> loadFood() => List.of(_food);

  @override
  void saveFood(FoodEntry entry) => _food.add(entry);

  @override
  void deleteFood(String id) => _food.removeWhere((e) => e.id == id);

  @override
  List<WorkoutSession> loadWorkouts() => List.of(_workouts);

  @override
  void saveWorkout(WorkoutSession session) {
    final i = _workouts.indexWhere((w) => w.id == session.id);
    if (i >= 0) {
      _workouts[i] = session;
    } else {
      _workouts.add(session);
    }
  }

  @override
  void deleteWorkout(String id) => _workouts.removeWhere((w) => w.id == id);

  @override
  List<PinnedCorrelation> loadPins() => List.of(_pins);

  @override
  void addPin(PinnedCorrelation pin) {
    if (!_pins.any((p) => p.key == pin.key)) _pins.add(pin);
  }

  @override
  void removePin(String key) => _pins.removeWhere((p) => p.key == key);

  @override
  void clear() {
    _logs.clear();
    _habits.clear();
    _completions.clear();
    _food.clear();
    _workouts.clear();
    _pins.clear();
  }

  InMemoryRepository seedDemo() {
    applyDemoSeed(this);
    return this;
  }
}

/// Shared first-run demo seed so the app shows real ranks immediately.
/// Strength lifts carry the bodyweight at the time of the lift.
void applyDemoSeed(Repository r) {
  final now = DateTime.now();
  void addProg(String id, List<double> vals, {double? bw, bool str = false}) {
    for (var i = 0; i < vals.length; i++) {
      final t = now.subtract(Duration(days: (vals.length - 1 - i) * 3));
      r.saveLog(id, Log(id, str ? strengthValue(id, vals[i], 5) : vals[i], bodyweight: bw, ts: t.toIso8601String()));
    }
  }

  addProg('bodyweight', [80, 79.5, 79, 78.5, 78]);
  addProg('bench', [75, 78, 80, 85, 90], bw: 78, str: true);
  addProg('squat', [110, 115, 120, 125, 130], bw: 78, str: true);

  addProg('ohp', [45, 48, 50, 52, 55], bw: 78, str: true);
  addProg('vo2max', [45, 46, 48, 49, 51]);
  addProg('resting_hr', [65, 63, 61, 60, 58]);
  addProg('plank', [90, 105, 120, 135, 150]);
  addProg('vert', [45, 47, 49, 50, 52]);
}

// ── Full backup / restore ───────────────────────────────────────────────────
// A complete JSON snapshot of every local entity, for cloud backup + transfer to a
// new device. Pure (works on any Repository via its public load/save API).

Map<String, dynamic> repoExport(Repository r) => {
      'v': 1,
      'logs': {
        for (final e in r.loadLogs().entries)
          e.key: [
            for (final l in e.value)
              {'v': l.value, if (l.bodyweight != null) 'bw': l.bodyweight, 'ts': l.ts}
          ]
      },
      'habits': [for (final h in r.loadHabits()) h.toJson()],
      'completions': {for (final e in r.loadCompletions().entries) e.key: e.value.toList()},
      'food': [for (final f in r.loadFood()) f.toJson()],
      'workouts': [for (final w in r.loadWorkouts()) w.toJson()],
      'pins': [for (final p in r.loadPins()) p.toJson()],
    };

/// Replace ALL local data with a snapshot from [repoExport]. No-op-safe on junk.
void repoImport(Repository r, Map<String, dynamic> m) {
  r.clear();
  ((m['logs'] as Map?) ?? const {}).forEach((mid, list) {
    for (final d in (list as List)) {
      final j = (d as Map);
      r.saveLog(mid as String, Log(mid, (j['v'] as num).toDouble(),
          bodyweight: (j['bw'] as num?)?.toDouble(), ts: j['ts'] as String?));
    }
  });
  for (final h in ((m['habits'] as List?) ?? const [])) {
    r.saveHabit(Habit.fromJson((h as Map).cast<String, dynamic>()));
  }
  ((m['completions'] as Map?) ?? const {}).forEach((hid, days) {
    for (final d in (days as List)) {
      r.setCompletion(hid as String, d as String, true);
    }
  });
  for (final f in ((m['food'] as List?) ?? const [])) {
    r.saveFood(FoodEntry.fromJson((f as Map).cast<String, dynamic>()));
  }
  for (final w in ((m['workouts'] as List?) ?? const [])) {
    r.saveWorkout(WorkoutSession.fromJson((w as Map).cast<String, dynamic>()));
  }
  for (final p in ((m['pins'] as List?) ?? const [])) {
    r.addPin(PinnedCorrelation.fromJson((p as Map).cast<String, dynamic>()));
  }
}
