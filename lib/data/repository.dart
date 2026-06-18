// data/repository.dart — the storage seam. Nothing in the UI touches storage
// directly; everything goes through Repository. Today it's in-memory; later the
// same interface backs the local cache + cloud canonical store, so swapping it
// touches no UI (the discipline the prototype already had with storage.js).
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
  void saveLog(String metricId, Log log) =>
      (_logs[metricId] ??= []).add(log);

  @override
  void deleteLog(String metricId, int index) {
    final list = _logs[metricId];
    if (list != null && index >= 0 && index < list.length) list.removeAt(index);
  }

  @override
  void clear() => _logs.clear();

  /// A little demo data so the first run shows real ranks immediately.
  InMemoryRepository seedDemo() {
    saveLog('bodyweight', Log('bodyweight', 78));
    // strength lifts carry the bodyweight at the time of the lift
    saveLog('bench', Log('bench', est1rm(90, 5), bodyweight: 78));
    saveLog('squat', Log('squat', est1rm(130, 5), bodyweight: 78));
    saveLog('deadlift', Log('deadlift', est1rm(160, 3), bodyweight: 78));
    saveLog('ohp', Log('ohp', est1rm(55, 5), bodyweight: 78));
    saveLog('vo2max', Log('vo2max', 51));
    saveLog('resting_hr', Log('resting_hr', 58));
    saveLog('plank', Log('plank', 150));
    saveLog('vert', Log('vert', 52));
    return this;
  }
}
