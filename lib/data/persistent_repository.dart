// data/persistent_repository.dart — on-device persistence behind the same
// Repository interface. Mirrors the prototype's "JSON blob in localStorage"
// approach using shared_preferences. Reads stay synchronous (served from an
// in-memory cache loaded once at startup); writes are write-through async.
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/rank_engine.dart' show Log;
import 'habits.dart';
import 'profile.dart';
import 'repository.dart';

class PersistentRepository implements Repository {
  static const _key = 'physical_logs_v1';
  static const _habitsKey = 'physical_habits_v1';
  static const _doneKey = 'physical_habit_done_v1';
  static const _profileKey = 'physical_profile_v1';
  final SharedPreferences _prefs;
  final Map<String, List<Log>> _cache;
  final List<Habit> _habits;
  final Map<String, Set<String>> _completions;
  ProfileData _profile;
  PersistentRepository._(this._prefs, this._cache, this._habits,
      this._completions, this._profile);

  /// Load once at startup. First run seeds demo data, then persists it.
  static Future<PersistentRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final repo = PersistentRepository._(
      prefs,
      raw == null ? {} : _decode(raw),
      _decodeHabits(prefs.getString(_habitsKey)),
      _decodeDone(prefs.getString(_doneKey)),
      _decodeProfile(prefs.getString(_profileKey)),
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
  ProfileData loadProfile() => _profile;

  @override
  void saveProfile(ProfileData profile) {
    _profile = profile;
    unawaited(_prefs.setString(_profileKey, jsonEncode(profile.toJson())));
  }

  @override
  void clear() {
    _cache.clear();
    _habits.clear();
    _completions.clear();
    _profile = ProfileData.empty;
    _persist();
    _persistHabits();
    _persistDone();
    unawaited(_prefs.remove(_profileKey));
  }

  static ProfileData _decodeProfile(String? s) => s == null
      ? ProfileData.empty
      : ProfileData.fromJson(jsonDecode(s) as Map<String, dynamic>);

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
