// data/persistent_repository.dart — on-device persistence behind the same
// Repository interface. Mirrors the prototype's "JSON blob in localStorage"
// approach using shared_preferences. Reads stay synchronous (served from an
// in-memory cache loaded once at startup); writes are write-through async.
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/rank_engine.dart' show Log;
import 'correlation.dart';
import 'diet.dart';
import 'habits.dart';
import 'repository.dart';
import 'workout.dart';

class PersistentRepository implements Repository {
  static const _key = 'physical_logs_v1';
  static const _habitsKey = 'physical_habits_v1';
  static const _doneKey = 'physical_habit_done_v1';
  static const _foodKey = 'physical_food_v1';
  static const _workoutKey = 'physical_workouts_v1';
  static const _pinsKey = 'physical_pins_v1';
  final SharedPreferences _prefs;
  final Map<String, List<Log>> _cache;
  final List<Habit> _habits;
  final Map<String, Set<String>> _completions;
  final List<FoodEntry> _food;
  final List<WorkoutSession> _workouts;
  final List<PinnedCorrelation> _pins;
  PersistentRepository._(this._prefs, this._cache, this._habits,
      this._completions, this._food, this._workouts, this._pins);

  /// Load once at startup. First run seeds demo data, then persists it.
  static Future<PersistentRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final repo = PersistentRepository._(
      prefs,
      raw == null ? {} : _decode(raw),
      _decodeHabits(prefs.getString(_habitsKey)),
      _decodeDone(prefs.getString(_doneKey)),
      _decodeFood(prefs.getString(_foodKey)),
      _decodeWorkouts(prefs.getString(_workoutKey)),
      _decodePins(prefs.getString(_pinsKey)),
    );
    if (raw == null) applyDemoSeed(repo); // first run only
    return repo;
  }

  @override
  Map<String, List<Log>> loadLogs() =>
      {for (final e in _cache.entries) e.key: List.of(e.value)};

  @override
  void saveLog(String metricId, Log log) {
    (_cache[metricId] ??= []).add(log);
    _persist();
  }

  @override
  void deleteLog(String metricId, int index) {
    final list = _cache[metricId];
    if (list != null && index >= 0 && index < list.length) list.removeAt(index);
    _persist();
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
    _persistHabits();
  }

  @override
  void deleteHabit(String id) {
    _habits.removeWhere((h) => h.id == id);
    _completions.remove(id);
    _persistHabits();
    _persistDone();
  }

  @override
  Map<String, Set<String>> loadCompletions() =>
      {for (final e in _completions.entries) e.key: Set.of(e.value)};

  @override
  void setCompletion(String habitId, String day, bool done) {
    final set = _completions[habitId] ??= <String>{};
    done ? set.add(day) : set.remove(day);
    _persistDone();
  }

  @override
  List<FoodEntry> loadFood() => List.of(_food);

  @override
  void saveFood(FoodEntry entry) {
    _food.add(entry);
    _persistFood();
  }

  @override
  void deleteFood(String id) {
    _food.removeWhere((e) => e.id == id);
    _persistFood();
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
    _persistWorkouts();
  }

  @override
  void deleteWorkout(String id) {
    _workouts.removeWhere((w) => w.id == id);
    _persistWorkouts();
  }

  @override
  List<PinnedCorrelation> loadPins() => List.of(_pins);

  @override
  void addPin(PinnedCorrelation pin) {
    if (!_pins.any((p) => p.key == pin.key)) {
      _pins.add(pin);
      _persistPins();
    }
  }

  @override
  void removePin(String key) {
    _pins.removeWhere((p) => p.key == key);
    _persistPins();
  }

  @override
  void clear() {
    _cache.clear();
    _habits.clear();
    _completions.clear();
    _food.clear();
    _workouts.clear();
    _pins.clear();
    _persist();
    _persistHabits();
    _persistDone();
    _persistFood();
    _persistWorkouts();
    _persistPins();
  }

  void _persistPins() => unawaited(_prefs.setString(
      _pinsKey, jsonEncode([for (final p in _pins) p.toJson()])));

  static List<PinnedCorrelation> _decodePins(String? s) => s == null
      ? []
      : [for (final p in (jsonDecode(s) as List)) PinnedCorrelation.fromJson(p as Map<String, dynamic>)];

  void _persistFood() => unawaited(_prefs.setString(
      _foodKey, jsonEncode([for (final e in _food) e.toJson()])));

  void _persistWorkouts() => unawaited(_prefs.setString(
      _workoutKey, jsonEncode([for (final w in _workouts) w.toJson()])));

  static List<FoodEntry> _decodeFood(String? s) => s == null
      ? []
      : [for (final e in (jsonDecode(s) as List)) FoodEntry.fromJson(e as Map<String, dynamic>)];

  static List<WorkoutSession> _decodeWorkouts(String? s) {
    if (s == null) return [];
    final out = <WorkoutSession>[];
    for (final w in (jsonDecode(s) as List)) {
      try {
        out.add(WorkoutSession.fromJson(w as Map<String, dynamic>));
      } catch (_) {/* skip an unparseable legacy entry */}
    }
    return out;
  }

  void _persist() => unawaited(_prefs.setString(_key, _encode(_cache)));

  void _persistHabits() => unawaited(_prefs.setString(
      _habitsKey, jsonEncode([for (final h in _habits) h.toJson()])));

  void _persistDone() => unawaited(_prefs.setString(_doneKey,
      jsonEncode({for (final e in _completions.entries) e.key: e.value.toList()})));

  static List<Habit> _decodeHabits(String? s) {
    if (s == null) return [];
    return [
      for (final x in (jsonDecode(s) as List))
        Habit.fromJson(x as Map<String, dynamic>)
    ];
  }

  static Map<String, Set<String>> _decodeDone(String? s) {
    if (s == null) return {};
    final j = jsonDecode(s) as Map<String, dynamic>;
    return {
      for (final e in j.entries)
        e.key: {for (final d in (e.value as List)) d as String}
    };
  }

  static String _encode(Map<String, List<Log>> m) => jsonEncode({
        for (final e in m.entries) e.key: [for (final l in e.value) _logToJson(l)]
      });

  static Map<String, List<Log>> _decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return {
      for (final e in j.entries)
        e.key: [
          for (final x in (e.value as List)) _logFromJson(x as Map<String, dynamic>)
        ]
    };
  }

  static Map<String, dynamic> _logToJson(Log l) =>
      {'m': l.metricId, 'v': l.value, 'bw': l.bodyweight, 'ts': l.ts};

  static Log _logFromJson(Map<String, dynamic> j) => Log(
        j['m'] as String,
        (j['v'] as num).toDouble(),
        bodyweight: (j['bw'] as num?)?.toDouble(),
        ts: j['ts'] as String?,
      );
}
