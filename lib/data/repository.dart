// data/repository.dart — the storage seam. Nothing in the UI touches storage
// directly; everything goes through Repository. InMemoryRepository is the
// fallback/default (and used in tests); PersistentRepository (shared_preferences)
// is wired in main.dart for real on-device storage. Same interface either way.
import '../engine/rank_engine.dart' show Log, est1rm;

abstract class Repository {
  Map<String, List<Log>> loadLogs();
  void saveLog(String metricId, Log log);
  void deleteLog(String metricId, int index);
  void clear();
}

class InMemoryRepository implements Repository {
  final Map<String, List<Log>> _logs = {};

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
  void clear() => _logs.clear();

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
      r.saveLog(id, Log(id, str ? est1rm(vals[i], 5) : vals[i], bodyweight: bw, ts: t.toIso8601String()));
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
