// data/api_client.dart — thin HTTP client for the FastAPI backend. The app is
// local-first; this is only used when the user opts to sync.
//
// Auth model: every per-user route is `/me/...` and reads the user from the JWT
// we send as `Authorization: Bearer <token>`. The client holds the token after
// sign-in; the backend scopes all data to that user.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => 'ApiException($status): $message';
}

/// Gemini-inferred nutrition for a food description (macros + canonical micros +
/// diet-health radar axis points).
class InferredNutrition {
  final double calories, protein, carbs, fat, fibre;
  final Map<String, double> micros;
  final Map<String, double> health;
  const InferredNutrition({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fibre,
    this.micros = const {},
    this.health = const {},
  });
}

/// JSON-encode, replacing any non-finite double (NaN / ±Infinity) with null. Dart's
/// jsonEncode otherwise writes `NaN`/`Infinity` literals → INVALID JSON the server
/// rejects, a device-data-dependent failure (e.g. the AI coach "didn't go through" on one
/// device but not another, because only its data produced such a value).
String _safeEncode(Object? o) => jsonEncode(_finiteOnly(o));
Object? _finiteOnly(Object? v) {
  if (v is double) return v.isFinite ? v : null;
  if (v is Map) return {for (final e in v.entries) e.key: _finiteOnly(e.value)};
  if (v is List) return [for (final e in v) _finiteOnly(e)];
  return v;
}

class ApiClient {
  final String baseUrl;
  final http.Client _client;
  String? _token;

  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  static const _tokenKey = 'physical_jwt';
  String? userEmail;

  bool get isSignedIn => _token != null;

  Map<String, String> _headers([Map<String, String>? extra]) => {
        if (_token != null) 'Authorization': 'Bearer $_token',
        ...?extra,
      };

  /// Load a previously-saved JWT (so sign-in is remembered across launches).
  Future<void> loadPersistedToken() async {
    _token ??= (await SharedPreferences.getInstance()).getString(_tokenKey);
  }

  Future<void> _persist(String token) async {
    _token = token;
    await (await SharedPreferences.getInstance()).setString(_tokenKey, token);
  }

  Future<void> signOut() async {
    _token = null;
    userEmail = null;
    await (await SharedPreferences.getInstance()).remove(_tokenKey);
  }

  /// Current account email (from a persisted token), or null if not signed in.
  Future<String?> whoAmI() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/auth/me'), headers: _headers())
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      userEmail = (jsonDecode(r.body) as Map<String, dynamic>)['email'] as String?;
      return userEmail;
    } catch (_) {
      return null;
    }
  }

  /// The Google consent URL for browser sign-in (identity + health in one).
  Future<String> googleSignInUrl() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/auth/google/url'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw ApiException('sign-in url failed: ${r.body}', r.statusCode);
    }
    return (jsonDecode(r.body) as Map<String, dynamic>)['authorize_url'] as String;
  }

  /// Scopes the LAST sign-in consent failed to grant (set by
  /// [googleSignInComplete]). Google can silently drop scopes — unticked consent
  /// checkboxes, or restricted health scopes when the OAuth consent screen isn't
  /// in Testing mode — which otherwise shows up only as 403s on every sync.
  List<String> lastSignInMissingScopes = const [];

  /// Complete sign-in with the OAuth code: stores the JWT (persisted) and returns
  /// the account email.
  Future<String?> googleSignInComplete(String code) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/auth/google/complete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code}))
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      throw ApiException('sign-in failed: ${r.body}', r.statusCode);
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    await _persist(j['access_token'] as String);
    userEmail = j['email'] as String?;
    lastSignInMissingScopes =
        ((j['missing_scopes'] as List?) ?? const []).cast<String>();
    return userEmail;
  }

  Future<bool> health() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Dev sign-in: get (and store) a JWT for a fixed dev user. Replaced by
  /// Google Sign-In on real devices.
  Future<void> devSignIn({String userId = 'local-dev'}) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/auth/dev'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw ApiException('sign-in failed: ${r.body}', r.statusCode);
    }
    await _persist((jsonDecode(r.body) as Map<String, dynamic>)['access_token'] as String);
  }

  /// Bulk-ingest canonical samples for the signed-in user.
  Future<Map<String, dynamic>> ingestSamples(
      List<Map<String, dynamic>> samples) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/samples'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode(samples))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw ApiException('ingest failed: ${r.body}', r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Overall + per-category + per-metric ranks for the signed-in user.
  Future<Map<String, dynamic>> fetchRanks() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/me/ranks'), headers: _headers())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw ApiException('ranks failed: ${r.body}', r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Canonical samples for the signed-in user, optionally filtered.
  Future<List<Map<String, dynamic>>> fetchSamples(
      {String? source, String? metricId, int limit = 2000}) async {
    final uri = Uri.parse('$baseUrl/me/samples').replace(queryParameters: {
      'limit': '$limit',
      if (source != null) 'source': source,
      if (metricId != null) 'metric_id': metricId,
    });
    final r = await _client.get(uri, headers: _headers()).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw ApiException('fetch samples failed: ${r.body}', r.statusCode);
    }
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  /// Whether the signed-in user has a Google Health connection.
  Future<bool> googleConnected() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/integrations/google/status'), headers: _headers())
          .timeout(const Duration(seconds: 8));
      return r.statusCode == 200 &&
          (jsonDecode(r.body) as Map)['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Google connection status incl. which scopes the stored token is missing
  /// (a token granted before a scope was added silently 403s those APIs until
  /// the user reconnects). {} on any failure.
  Future<Map<String, dynamic>> googleStatus() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/integrations/google/status'), headers: _headers())
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return const {};
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  /// The consent URL for the SEPARATE Google Calendar grant. Calendar can't ride
  /// on the health token — the Health API rejects tokens carrying calendar.events.
  Future<String> googleCalendarAuthorizeUrl() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/integrations/google/calendar/authorize'),
            headers: _headers())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw ApiException('calendar authorize failed: ${r.body}', r.statusCode);
    }
    return (jsonDecode(r.body) as Map<String, dynamic>)['authorize_url'] as String;
  }

  /// Exchange the calendar consent code → stores the calendar token server-side.
  Future<void> googleCalendarExchange(String code) async {
    final uri = Uri.parse('$baseUrl/integrations/google/calendar/exchange')
        .replace(queryParameters: {'code': code});
    final r = await _client.post(uri, headers: _headers()).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw ApiException('calendar exchange failed: ${r.body}', r.statusCode);
    }
  }

  /// Delete the signed-in user's cloud samples (all, or scoped by source/metric).
  /// Returns how many were deleted. Throws on failure.
  Future<int> deleteCloudSamples({String? source, String? metricId}) async {
    final uri = Uri.parse('$baseUrl/me/samples').replace(queryParameters: {
      if (source != null) 'source': source,
      if (metricId != null) 'metric_id': metricId,
    });
    final r = await _client
        .delete(uri, headers: _headers())
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return ((jsonDecode(r.body) as Map)['deleted'] as num?)?.toInt() ?? 0;
  }

  /// LLM habit verification: sends the day's habits + evidence, returns one
  /// verdict per habit [{id, done, reason}], or null when unavailable (offline /
  /// unconfigured) so the caller can fall back to the rule-based check.
  Future<List<Map<String, dynamic>>?> verifyHabits({
    required String day,
    required List<Map<String, dynamic>> habits,
    List<Map<String, dynamic>> workouts = const [],
    List<Map<String, dynamic>> food = const [],
    Map<String, dynamic> metrics = const {},
  }) async {
    try {
      final r = await _client
          .post(Uri.parse('$baseUrl/me/habits/verify'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: _safeEncode({
                'day': day,
                'habits': habits,
                'workouts': workouts,
                'food': food,
                'metrics': metrics,
              }))
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return ((j['verdicts'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  /// The Google consent URL for the signed-in user to open in a browser.
  Future<String> googleAuthorizeUrl() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/integrations/google/authorize'), headers: _headers())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw ApiException('authorize failed: ${r.body}', r.statusCode);
    }
    return (jsonDecode(r.body) as Map<String, dynamic>)['authorize_url'] as String;
  }

  /// Exchange the OAuth code (from the consent redirect) for stored tokens.
  Future<void> googleExchange(String code) async {
    final uri = Uri.parse('$baseUrl/integrations/google/exchange')
        .replace(queryParameters: {'code': code});
    final r = await _client.post(uri, headers: _headers()).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw ApiException('exchange failed: ${r.body}', r.statusCode);
    }
  }

  /// Ask the backend to pull fresh data from the user's Google Health.
  /// The user's Google Health profile age (for auto-porting), or null.
  Future<int?> googleProfileAge() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/integrations/google/profile'), headers: _headers())
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map<String, dynamic>)['age'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Recent Google exercise SESSIONS (parsed), for importing into the Exercise section.
  Future<List<Map<String, dynamic>>> googleExercises() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/integrations/google/exercises'), headers: _headers())
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return const [];
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return ((body['sessions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  // Calendar pushes are SERIALIZED app-wide: the connect flow, the sync, and the
  // habit-change debounce can all fire around the same moment, and overlapping
  // reconciles waste calls (the deterministic event ids server-side already make
  // duplicates impossible; this keeps the traffic clean too).
  static Future<void> _calendarPushChain = Future.value();

  /// Push habits into the user's Google Calendar (reconcile: upsert one event
  /// per habit, delete strays + removed habits). Returns {added, updated,
  /// removed, deduped, failed}. Throws ApiException(401/403) when the calendar
  /// consent is needed, 412 when the Calendar API is disabled in the project.
  Future<Map<String, dynamic>> pushCalendar(
      List<Map<String, dynamic>> habits, String? tz) {
    final result = _calendarPushChain.then((_) => _pushCalendarNow(habits, tz));
    _calendarPushChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, dynamic>> _pushCalendarNow(
      List<Map<String, dynamic>> habits, String? tz) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/calendar/push'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: _safeEncode({'habits': habits, if (tz != null) 'tz': tz}))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// The user's personal habit-calendar subscription URL (https), or null if signed out.
  Future<String?> calendarFeedUrl() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/me/calendar-feed'), headers: _headers())
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map<String, dynamic>)['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> googleFoods() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/integrations/google/foods'), headers: _headers())
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return const [];
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return ((body['foods'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  /// Push a full local-data snapshot to the cloud (PUT /me/backup). Returns bytes stored.
  Future<int> pushBackup(Map<String, dynamic> snapshot) async {
    final r = await _client
        .put(Uri.parse('$baseUrl/me/backup'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode(snapshot))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return ((jsonDecode(r.body) as Map)['bytes'] as num?)?.toInt() ?? 0;
  }

  /// Delete the cloud snapshot — part of 'reset cloud data' (without it, deleted
  /// entities ride back in on the next sync's backup merge).
  Future<void> deleteBackup() async {
    final r = await _client
        .delete(Uri.parse('$baseUrl/me/backup'), headers: _headers())
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
  }

  /// Pull the cloud snapshot (GET /me/backup), or null if none exists yet.
  Future<Map<String, dynamic>?> pullBackup() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/me/backup'), headers: _headers())
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return (jsonDecode(r.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  /// Upload a recorded voice clip (WAV) for clinical voice-quality analysis.
  /// Returns the backend result (score + jitter/shimmer/HNR/pitch). Throws on failure.
  Future<Map<String, dynamic>> measureVoice(String filePath) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/me/aesthetics/voice'))
      ..headers.addAll(_headers())
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await _client.send(req).timeout(const Duration(seconds: 30));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) {
      String msg;
      try {
        msg = (jsonDecode(r.body) as Map)['detail']?.toString() ?? r.body;
      } catch (_) {
        msg = r.body;
      }
      throw ApiException(msg, r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Upload a photo for an aesthetic CV measurement (metric ∈ skin|oral|hair).
  /// [fovMm] is the macro lens' field-of-view width (hair → hairs/cm²). Throws on failure.
  Future<Map<String, dynamic>> measurePhoto(String metric, String filePath,
      {double? fovMm}) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/me/aesthetics/photo/$metric'))
      ..headers.addAll(_headers())
      ..fields['fov_mm'] = (fovMm ?? 20.0).toString()
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await _client.send(req).timeout(const Duration(seconds: 45));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) {
      String msg;
      try {
        msg = (jsonDecode(r.body) as Map)['detail']?.toString() ?? r.body;
      } catch (_) {
        msg = r.body;
      }
      throw ApiException(msg, r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Raw Google Health debug output (status + a real sample per data type, plus
  /// profile/session probes) — returned verbatim for the in-app inspector to copy.
  Future<String> googleDebug() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/integrations/google/debug'), headers: _headers())
        .timeout(const Duration(seconds: 45));
    return r.body;
  }

  Future<Map<String, dynamic>> triggerGoogleSync({int days = 7}) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/integrations/google/sync?days=$days'),
            headers: _headers())
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw ApiException('google sync failed: ${r.body}', r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ── AI coach (PDF Part 5) ──
  Future<Map<String, dynamic>> coachStatus() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/me/coach/status'), headers: _headers())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Returns {reply: String, actions: List} — actions are confirmable habit
  /// changes the coach proposed.
  Future<Map<String, dynamic>> coachChat({
    required String message,
    List<Map<String, String>> history = const [],
    List<Map<String, dynamic>> habits = const [],
    Map<String, dynamic>? profile,
    Map<String, dynamic>? diet,
    Map<String, dynamic>? training,
    Map<String, dynamic>? aesthetics,
    Map<String, dynamic>? ranks,
    Map<String, dynamic>? trends,
    List<Map<String, dynamic>> correlations = const [],
    List<Map<String, dynamic>> workoutSets = const [],
    Map<String, List<double>> metricHistory = const {},
    Map<String, dynamic>? energy,
    List<Map<String, dynamic>> meals = const [],
  }) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/coach/chat'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: _safeEncode({
              'message': message,
              'history': history,
              'habits': habits,
              if (profile != null) 'profile': profile,
              if (diet != null) 'diet': diet,
              if (training != null) 'training': training,
              if (aesthetics != null) 'aesthetics': aesthetics,
              if (ranks != null) 'ranks': ranks,
              if (trends != null) 'trends': trends,
              if (correlations.isNotEmpty) 'correlations': correlations,
              if (workoutSets.isNotEmpty) 'workout_sets': workoutSets,
              if (metricHistory.isNotEmpty) 'metric_history': metricHistory,
              if (energy != null && energy.isNotEmpty) 'energy': energy,
              if (meals.isNotEmpty) 'meals': meals,
            }))
        .timeout(const Duration(seconds: 120));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// AI weekly habit-roster builder: full context + an optional emphasised
  /// [goal] → {summary, habits: [{title, section, verify, target, …, plan?}]}.
  /// The caller shows it as a review sheet; nothing is applied automatically.
  Future<Map<String, dynamic>> coachPlan({
    String goal = '',
    List<Map<String, dynamic>> habits = const [],
    Map<String, dynamic>? profile,
    Map<String, dynamic>? diet,
    Map<String, dynamic>? training,
    Map<String, dynamic>? aesthetics,
    Map<String, dynamic>? ranks,
    Map<String, dynamic>? trends,
    List<Map<String, dynamic>> correlations = const [],
    List<Map<String, dynamic>> workoutSets = const [],
    Map<String, List<double>> metricHistory = const {},
    Map<String, dynamic>? energy,
    List<Map<String, dynamic>> meals = const [],
  }) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/coach/plan'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: _safeEncode({
              'message': goal,
              'habits': habits,
              if (profile != null) 'profile': profile,
              if (diet != null) 'diet': diet,
              if (training != null) 'training': training,
              if (aesthetics != null) 'aesthetics': aesthetics,
              if (ranks != null) 'ranks': ranks,
              if (trends != null) 'trends': trends,
              if (correlations.isNotEmpty) 'correlations': correlations,
              if (workoutSets.isNotEmpty) 'workout_sets': workoutSets,
              if (metricHistory.isNotEmpty) 'metric_history': metricHistory,
              if (energy != null && energy.isNotEmpty) 'energy': energy,
              if (meals.isNotEmpty) 'meals': meals,
            }))
        .timeout(const Duration(seconds: 120));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// A short, AI-personalised notification line from the user's live context (or null).
  /// [slot] is 'morning' (day ahead) or 'evening' (reflect on today).
  Future<String?> coachNudge({
    String slot = 'morning',
    List<Map<String, dynamic>> habits = const [],
    Map<String, dynamic>? ranks,
    Map<String, dynamic>? trends,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? diet,
  }) async {
    try {
      final r = await _client
          .post(Uri.parse('$baseUrl/me/coach/nudge'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: _safeEncode({
                'message': slot,
                'habits': habits,
                if (ranks != null) 'ranks': ranks,
                if (trends != null) 'trends': trends,
                if (profile != null) 'profile': profile,
                if (diet != null) 'diet': diet,
              }))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return null;
      final s = (jsonDecode(r.body) as Map<String, dynamic>)['nudge'] as String?;
      return (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether nutrition auto-fill is available (Gemini configured server-side).
  Future<bool> nutritionConfigured() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/me/nutrition/status'), headers: _headers())
          .timeout(const Duration(seconds: 10));
      return r.statusCode == 200 && (jsonDecode(r.body) as Map)['configured'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Gemini-inferred nutrition for a food description (macros + micros); throws on error.
  Future<InferredNutrition> inferNutrition(String description) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/nutrition'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({'description': description}))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return InferredNutrition(
      calories: (j['calories'] as num).toDouble(),
      protein: (j['protein'] as num).toDouble(),
      carbs: (j['carbs'] as num).toDouble(),
      fat: (j['fat'] as num).toDouble(),
      fibre: (j['fibre'] as num).toDouble(),
      micros: {
        for (final e in ((j['micros'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toDouble()
      },
      health: {
        for (final e in ((j['health'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toDouble()
      },
    );
  }

  /// Exactly what the coach sees — for the transparency view.
  Future<Map<String, dynamic>> coachContext({
    List<Map<String, dynamic>> habits = const [],
    Map<String, dynamic>? profile,
    Map<String, dynamic>? diet,
    Map<String, dynamic>? training,
    Map<String, dynamic>? aesthetics,
    Map<String, dynamic>? ranks,
    Map<String, dynamic>? trends,
    List<Map<String, dynamic>> correlations = const [],
    List<Map<String, dynamic>> workoutSets = const [],
    Map<String, dynamic>? metricHistory,
    Map<String, dynamic>? energy,
    List<Map<String, dynamic>> meals = const [],
  }) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/coach/context'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: _safeEncode({
              'habits': habits,
              if (profile != null) 'profile': profile,
              if (diet != null) 'diet': diet,
              if (training != null) 'training': training,
              if (aesthetics != null) 'aesthetics': aesthetics,
              if (ranks != null) 'ranks': ranks,
              if (trends != null) 'trends': trends,
              if (correlations.isNotEmpty) 'correlations': correlations,
              if (workoutSets.isNotEmpty) 'workout_sets': workoutSets,
              if (metricHistory != null) 'metric_history': metricHistory,
              if (energy != null) 'energy': energy,
              if (meals.isNotEmpty) 'meals': meals,
            }))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
