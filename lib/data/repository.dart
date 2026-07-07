// data/repository.dart — the storage seam. Nothing in the UI touches storage
// directly; everything goes through Repository. InMemoryRepository is the
// fallback/default (and used in tests); PersistentRepository (shared_preferences)
// is wired in main.dart for real on-device storage. Same interface either way.
import '../engine/rank_engine.dart' show Log, strengthValue;
import 'correlation.dart';
import 'diet.dart';
import 'habits.dart';
import 'pins.dart';
import 'workout.dart';

/// Stable key for a single log ("metricId@ts") — used for dedupe + tombstones.
String logKey(String metricId, Log l) => '$metricId@${l.ts}';

/// Tombstone key for a deleted ENTITY (habit/food/workout/template). Without
/// these, a deleted habit rides back in on the next sync's cloud-backup merge —
/// the union can't tell "deleted here" from "created there".
String entityKey(String kind, String id) => '$kind:$id';

/// The derived, fully recomputable log series (rank history + readiness). These
/// are EXCLUDED from backup export/merge and from the cloud sample push: they're
/// pure functions of the real logs, and letting old copies ride the cloud
/// snapshot meant "Rebuild rank history" was undone by the very next sync
/// (stale category ranks resurrected from the backup blob).
const List<String> derivedSeriesIds = [
  'overall_rank', 'strength_rank', 'performance_rank', 'recovery_rank',
  'aesthetics_rank', 'daily_readiness',
];

abstract class Repository {
  Map<String, List<Log>> loadLogs();
  void saveLog(String metricId, Log log);
  void deleteLog(String metricId, int index);

  /// Replace the log at [index] in place (same slot, new value) — used when a
  /// synced daily value is revised (e.g. today's step total grows through the
  /// day) so history stays live instead of frozen at first sight.
  void replaceLog(String metricId, int index, Log log);

  /// Delete every log of a metric WITHOUT tombstoning — for derived, fully
  /// recomputable series (rank history, readiness) that a reset re-backfills at
  /// the same timestamps (a tombstone would block the re-add forever).
  void purgeMetricLogs(String metricId);
  void clear();

  // Tombstones: keys ("metricId@ts") of deleted logs, so a delete STICKS — Google
  // re-sync and the cloud backup merge won't resurrect them across syncs/devices.
  Set<String> loadTombstones();
  void addTombstone(String key);

  // Habits (Phase 2) — accountability layer, stored separately from logs.
  List<Habit> loadHabits();
  void saveHabit(Habit habit);
  void deleteHabit(String id);
  Map<String, Set<String>> loadCompletions(); // habitId → set of done date-keys
  void setCompletion(String habitId, String day, bool done);

  // AI verification verdicts (LLM habit check): habitId → day → done. A verdict
  // overrides the rule-based auto-check for that habit+day (manual habits are
  // never judged). Stored separately from completions so a manual tick can
  // never masquerade as verified evidence.
  Map<String, Map<String, bool>> loadAiVerdicts();
  void setAiVerdict(String habitId, String day, bool done);

  // Workout templates (fast set logging — save a workout's sets, start new
  // sessions pre-filled).
  List<WorkoutTemplate> loadTemplates();
  void saveTemplate(WorkoutTemplate template);
  void deleteTemplate(String id);

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

  // Profile facts (ride the backup blob). DOB drives the auto-refreshed 'age'
  // log — age is derived on birthdays, never left frozen at what was typed.
  String? loadDob(); // ISO date, YYYY-MM-DD
  void saveDob(String dob);

  // AI pins — free-text goals/context the coach must always remember (the
  // Habits tab's pin section; sent with every coach request). Tombstoned like
  // other entities so a delete sticks across devices.
  List<AiPin> loadAiPins();
  void saveAiPin(AiPin pin);
  void deleteAiPin(String id);
}

class InMemoryRepository implements Repository {
  final Map<String, List<Log>> _logs = {};
  final Set<String> _tombstones = {};
  final List<Habit> _habits = [];
  final Map<String, Set<String>> _completions = {};
  final Map<String, Map<String, bool>> _aiVerdicts = {};
  final List<FoodEntry> _food = [];
  final List<WorkoutSession> _workouts = [];
  final List<WorkoutTemplate> _templates = [];
  final List<PinnedCorrelation> _pins = [];
  final List<AiPin> _aiPins = [];
  String? _dob;

  @override
  Map<String, List<Log>> loadLogs() =>
      {for (final e in _logs.entries) e.key: List.of(e.value)};

  @override
  void saveLog(String metricId, Log log) => (_logs[metricId] ??= []).add(log);

  @override
  void deleteLog(String metricId, int index) {
    final list = _logs[metricId];
    if (list != null && index >= 0 && index < list.length) {
      _tombstones.add(logKey(metricId, list[index]));
      list.removeAt(index);
    }
  }

  @override
  void replaceLog(String metricId, int index, Log log) {
    final list = _logs[metricId];
    if (list != null && index >= 0 && index < list.length) list[index] = log;
  }

  @override
  void purgeMetricLogs(String metricId) => _logs.remove(metricId);

  @override
  Set<String> loadTombstones() => Set.of(_tombstones);
  @override
  void addTombstone(String key) => _tombstones.add(key);

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
    _aiVerdicts.remove(id);
    _tombstones.add(entityKey('habit', id));
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
  Map<String, Map<String, bool>> loadAiVerdicts() =>
      {for (final e in _aiVerdicts.entries) e.key: Map.of(e.value)};

  @override
  void setAiVerdict(String habitId, String day, bool done) =>
      (_aiVerdicts[habitId] ??= {})[day] = done;

  @override
  List<WorkoutTemplate> loadTemplates() => List.of(_templates);

  @override
  void saveTemplate(WorkoutTemplate template) {
    final i = _templates.indexWhere((t) => t.id == template.id);
    if (i >= 0) {
      _templates[i] = template;
    } else {
      _templates.add(template);
    }
  }

  @override
  void deleteTemplate(String id) {
    _templates.removeWhere((t) => t.id == id);
    _tombstones.add(entityKey('template', id));
  }

  @override
  List<FoodEntry> loadFood() => List.of(_food);

  @override
  void saveFood(FoodEntry entry) {
    final i = _food.indexWhere((f) => f.id == entry.id);
    if (i >= 0) {
      _food[i] = entry; // upsert — re-saving an enriched food must not duplicate it
    } else {
      _food.add(entry);
    }
  }

  @override
  void deleteFood(String id) {
    _food.removeWhere((e) => e.id == id);
    _tombstones.add(entityKey('food', id));
  }

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
  void deleteWorkout(String id) {
    _workouts.removeWhere((w) => w.id == id);
    _tombstones.add(entityKey('workout', id));
  }

  @override
  List<PinnedCorrelation> loadPins() => List.of(_pins);

  @override
  void addPin(PinnedCorrelation pin) {
    if (!_pins.any((p) => p.key == pin.key)) _pins.add(pin);
  }

  @override
  void removePin(String key) => _pins.removeWhere((p) => p.key == key);

  @override
  String? loadDob() => _dob;

  @override
  void saveDob(String dob) => _dob = dob;

  @override
  List<AiPin> loadAiPins() => List.of(_aiPins);

  @override
  void saveAiPin(AiPin pin) {
    final i = _aiPins.indexWhere((p) => p.id == pin.id);
    if (i >= 0) {
      _aiPins[i] = pin;
    } else {
      _aiPins.add(pin);
    }
  }

  @override
  void deleteAiPin(String id) {
    _aiPins.removeWhere((p) => p.id == id);
    _tombstones.add(entityKey('aipin', id));
  }

  @override
  void clear() {
    _logs.clear();
    _tombstones.clear();
    _habits.clear();
    _completions.clear();
    _aiVerdicts.clear();
    _food.clear();
    _workouts.clear();
    _templates.clear();
    _pins.clear();
    _aiPins.clear();
    _dob = null;
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
          if (!derivedSeriesIds.contains(e.key))
            e.key: [
              for (final l in e.value)
                {'v': l.value, if (l.bodyweight != null) 'bw': l.bodyweight, 'ts': l.ts}
            ]
      },
      'habits': [for (final h in r.loadHabits()) h.toJson()],
      'completions': {for (final e in r.loadCompletions().entries) e.key: e.value.toList()},
      'aiVerdicts': {
        for (final e in r.loadAiVerdicts().entries)
          if (e.value.isNotEmpty) e.key: e.value
      },
      'food': [for (final f in r.loadFood()) f.toJson()],
      'workouts': [for (final w in r.loadWorkouts()) w.toJson()],
      'templates': [for (final t in r.loadTemplates()) t.toJson()],
      'pins': [for (final p in r.loadPins()) p.toJson()],
      'aiPins': [for (final p in r.loadAiPins()) p.toJson()],
      if (r.loadDob() != null) 'dob': r.loadDob(),
      'tombstones': r.loadTombstones().toList(),
    };

/// Replace ALL local data with a snapshot from [repoExport]. No-op-safe on junk.
void repoImport(Repository r, Map<String, dynamic> m) {
  r.clear();
  // Restore tombstones first so a resurrected log in the snapshot can't slip back in.
  final tombs = {for (final t in ((m['tombstones'] as List?) ?? const [])) t as String};
  for (final t in tombs) {
    r.addTombstone(t);
  }
  ((m['logs'] as Map?) ?? const {}).forEach((mid, list) {
    if (derivedSeriesIds.contains(mid)) return; // recomputed, never restored
    for (final d in (list as List)) {
      final j = (d as Map);
      final ts = j['ts'] as String?;
      if (ts != null && tombs.contains('$mid@$ts')) continue;
      r.saveLog(mid as String, Log(mid, (j['v'] as num).toDouble(),
          bodyweight: (j['bw'] as num?)?.toDouble(), ts: ts));
    }
  });
  for (final h in ((m['habits'] as List?) ?? const [])) {
    final j = (h as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('habit', j['id'] as String))) continue;
    r.saveHabit(Habit.fromJson(j));
  }
  ((m['completions'] as Map?) ?? const {}).forEach((hid, days) {
    for (final d in (days as List)) {
      r.setCompletion(hid as String, d as String, true);
    }
  });
  ((m['aiVerdicts'] as Map?) ?? const {}).forEach((hid, days) {
    ((days as Map?) ?? const {}).forEach((day, done) {
      r.setAiVerdict(hid as String, day as String, done == true);
    });
  });
  for (final f in ((m['food'] as List?) ?? const [])) {
    final j = (f as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('food', j['id'] as String))) continue;
    r.saveFood(FoodEntry.fromJson(j));
  }
  for (final w in ((m['workouts'] as List?) ?? const [])) {
    final j = (w as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('workout', j['id'] as String))) continue;
    r.saveWorkout(WorkoutSession.fromJson(j));
  }
  for (final t in ((m['templates'] as List?) ?? const [])) {
    final j = (t as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('template', j['id'] as String))) continue;
    r.saveTemplate(WorkoutTemplate.fromJson(j));
  }
  for (final p in ((m['pins'] as List?) ?? const [])) {
    r.addPin(PinnedCorrelation.fromJson((p as Map).cast<String, dynamic>()));
  }
  for (final p in ((m['aiPins'] as List?) ?? const [])) {
    final j = (p as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('aipin', j['id'] as String))) continue;
    r.saveAiPin(AiPin.fromJson(j));
  }
  final dob = m['dob'] as String?;
  if (dob != null) r.saveDob(dob);
}

/// MERGE a snapshot into the existing store (union, never clears) — for multi-device
/// sync so two devices converge instead of one clobbering the other. Dedup rules:
/// logs by metric+timestamp, food/workouts/habits/templates by id, completions
/// set-union, pins by key. DELETES PROPAGATE: log + entity tombstones from either
/// side win over the other's copy, so a deleted habit can never ride back in on a
/// backup merge.
void repoMerge(Repository r, Map<String, dynamic> m) {
  // Union tombstones first, so deletions from EITHER device win over the other's copy.
  for (final t in ((m['tombstones'] as List?) ?? const [])) {
    r.addTombstone(t as String);
  }
  final tombs = r.loadTombstones();
  // Purge any local logs that are now tombstoned (a delete that happened on another device).
  r.loadLogs().forEach((mid, list) {
    for (var i = list.length - 1; i >= 0; i--) {
      if (tombs.contains(logKey(mid, list[i]))) r.deleteLog(mid, i);
    }
  });
  // Purge local entities the snapshot knows were deleted elsewhere.
  for (final h in r.loadHabits()) {
    if (tombs.contains(entityKey('habit', h.id))) r.deleteHabit(h.id);
  }
  for (final f in r.loadFood()) {
    if (tombs.contains(entityKey('food', f.id))) r.deleteFood(f.id);
  }
  for (final w in r.loadWorkouts()) {
    if (tombs.contains(entityKey('workout', w.id))) r.deleteWorkout(w.id);
  }
  for (final t in r.loadTemplates()) {
    if (tombs.contains(entityKey('template', t.id))) r.deleteTemplate(t.id);
  }
  for (final p in r.loadAiPins()) {
    if (tombs.contains(entityKey('aipin', p.id))) r.deleteAiPin(p.id);
  }
  final existingLogs = r.loadLogs();
  ((m['logs'] as Map?) ?? const {}).forEach((mid, list) {
    // Derived rank/readiness series are recomputed locally, never merged — old
    // snapshot copies used to undo "Rebuild rank history" on the next sync.
    if (derivedSeriesIds.contains(mid)) return;
    final haveTs = {for (final l in (existingLogs[mid] ?? const <Log>[])) l.ts};
    for (final d in (list as List)) {
      final j = (d as Map);
      final ts = j['ts'] as String?;
      if (ts != null && haveTs.contains(ts)) continue;
      if (ts != null && tombs.contains('$mid@$ts')) continue; // deleted — don't resurrect
      r.saveLog(mid as String, Log(mid, (j['v'] as num).toDouble(),
          bodyweight: (j['bw'] as num?)?.toDouble(), ts: ts));
    }
  });
  final haveHabits = {for (final h in r.loadHabits()) h.id};
  for (final h in ((m['habits'] as List?) ?? const [])) {
    final j = (h as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('habit', j['id'] as String))) continue;
    if (!haveHabits.contains(j['id'])) r.saveHabit(Habit.fromJson(j));
  }
  ((m['completions'] as Map?) ?? const {}).forEach((hid, days) {
    for (final d in (days as List)) {
      r.setCompletion(hid as String, d as String, true);
    }
  });
  // AI verdicts: only fill gaps — a verdict recomputed on THIS device (fresher
  // evidence) wins over the snapshot's copy.
  final haveVerdicts = r.loadAiVerdicts();
  ((m['aiVerdicts'] as Map?) ?? const {}).forEach((hid, days) {
    ((days as Map?) ?? const {}).forEach((day, done) {
      if (!(haveVerdicts[hid]?.containsKey(day) ?? false)) {
        r.setAiVerdict(hid as String, day as String, done == true);
      }
    });
  });
  final haveFood = {for (final f in r.loadFood()) f.id};
  for (final f in ((m['food'] as List?) ?? const [])) {
    final j = (f as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('food', j['id'] as String))) continue;
    if (!haveFood.contains(j['id'])) r.saveFood(FoodEntry.fromJson(j));
  }
  final haveWorkouts = {for (final w in r.loadWorkouts()) w.id};
  for (final w in ((m['workouts'] as List?) ?? const [])) {
    final j = (w as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('workout', j['id'] as String))) continue;
    if (!haveWorkouts.contains(j['id'])) r.saveWorkout(WorkoutSession.fromJson(j));
  }
  final haveTemplates = {for (final t in r.loadTemplates()) t.id};
  for (final t in ((m['templates'] as List?) ?? const [])) {
    final j = (t as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('template', j['id'] as String))) continue;
    if (!haveTemplates.contains(j['id'])) r.saveTemplate(WorkoutTemplate.fromJson(j));
  }
  final havePins = {for (final p in r.loadPins()) p.key};
  for (final p in ((m['pins'] as List?) ?? const [])) {
    final pin = PinnedCorrelation.fromJson((p as Map).cast<String, dynamic>());
    if (!havePins.contains(pin.key)) r.addPin(pin);
  }
  final haveAiPins = {for (final p in r.loadAiPins()) p.id};
  for (final p in ((m['aiPins'] as List?) ?? const [])) {
    final j = (p as Map).cast<String, dynamic>();
    if (tombs.contains(entityKey('aipin', j['id'] as String))) continue;
    if (!haveAiPins.contains(j['id'])) r.saveAiPin(AiPin.fromJson(j));
  }
  // DOB is an immutable fact — fill the gap, never overwrite a local value.
  final dob = m['dob'] as String?;
  if (dob != null && r.loadDob() == null) r.saveDob(dob);
}
