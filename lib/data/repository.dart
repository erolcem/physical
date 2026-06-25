// data/repository.dart — the storage seam. Nothing in the UI touches storage
// directly; everything goes through Repository. InMemoryRepository is the
// fallback/default (and used in tests); PersistentRepository (shared_preferences)
// is wired in main.dart for real on-device storage. Same interface either way.
import '../engine/rank_engine.dart' show Log, strengthValue;
import 'habits.dart';
import 'profile.dart';

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

  // Profile (PDF Part 1) — static identity fields, stored separately.
  ProfileData loadProfile();
  void saveProfile(ProfileData profile);
}

class InMemoryRepository implements Repository {
  final Map<String, List<Log>> _logs = {};
  final List<Habit> _habits = [];
  final Map<String, Set<String>> _completions = {};
  ProfileData _profile = ProfileData.empty;

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
  ProfileData loadProfile() => _profile;

  @override
  void saveProfile(ProfileData profile) => _profile = profile;

  @override
  void clear() {
    _logs.clear();
    _habits.clear();
    _completions.clear();
    _profile = ProfileData.empty;
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
