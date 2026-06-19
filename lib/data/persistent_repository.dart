// data/persistent_repository.dart — on-device persistence behind the same
// Repository interface. Mirrors the prototype's "JSON blob in localStorage"
// approach using shared_preferences. Reads stay synchronous (served from an
// in-memory cache loaded once at startup); writes are write-through async.
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/rank_engine.dart' show Log;
import 'repository.dart';

class PersistentRepository implements Repository {
  static const _key = 'physical_logs_v1';
  final SharedPreferences _prefs;
  final Map<String, List<Log>> _cache;
  PersistentRepository._(this._prefs, this._cache);

  /// Load once at startup. First run seeds demo data, then persists it.
  static Future<PersistentRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final repo = PersistentRepository._(prefs, raw == null ? {} : _decode(raw));
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
  void clear() {
    _cache.clear();
    _persist();
  }

  void _persist() => unawaited(_prefs.setString(_key, _encode(_cache)));

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
