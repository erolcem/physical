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

/// Gemini-inferred nutrition for a food description (macros + canonical micros).
class InferredNutrition {
  final double calories, protein, carbs, fat, fibre;
  final Map<String, double> micros;
  const InferredNutrition({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fibre,
    this.micros = const {},
  });
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

  // ── Friends (PDF Part 6) ──
  Future<Map<String, dynamic>> addFriend(String email) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/friends'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({'email': email}))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listFriends() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/me/friends'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> pendingFriendRequests() async {
    final r = await _client
        .get(Uri.parse('$baseUrl/me/friends/requests'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> acceptFriend(String requesterId) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/friends/$requesterId/accept'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
  }

  Future<void> removeFriend(String otherId) async {
    final r = await _client
        .delete(Uri.parse('$baseUrl/me/friends/$otherId'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
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
  }) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/coach/chat'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({
              'message': message,
              'history': history,
              'habits': habits,
              if (profile != null) 'profile': profile,
              if (diet != null) 'diet': diet,
              if (training != null) 'training': training,
              if (aesthetics != null) 'aesthetics': aesthetics,
            }))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
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
    );
  }

  /// Exactly what the coach sees — for the transparency view.
  Future<Map<String, dynamic>> coachContext({
    List<Map<String, dynamic>> habits = const [],
    Map<String, dynamic>? profile,
    Map<String, dynamic>? diet,
    Map<String, dynamic>? training,
    Map<String, dynamic>? aesthetics,
  }) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/me/coach/context'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({
              'habits': habits,
              if (profile != null) 'profile': profile,
              if (diet != null) 'diet': diet,
              if (training != null) 'training': training,
              if (aesthetics != null) 'aesthetics': aesthetics,
            }))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiException(r.body, r.statusCode);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
