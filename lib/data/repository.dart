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
  r.saveLog('bodyweight', Log('bodyweight', 78));
  r.saveLog('bench', Log('bench', est1rm(90, 5), bodyweight: 78));
  r.saveLog('squat', Log('squat', est1rm(130, 5), bodyweight: 78));
  r.saveLog('deadlift', Log('deadlift', est1rm(160, 3), bodyweight: 78));
  r.saveLog('ohp', Log('ohp', est1rm(55, 5), bodyweight: 78));
  r.saveLog('vo2max', Log('vo2max', 51));
  r.saveLog('resting_hr', Log('resting_hr', 58));
  r.saveLog('plank', Log('plank', 150));
  r.saveLog('vert', Log('vert', 52));
}
