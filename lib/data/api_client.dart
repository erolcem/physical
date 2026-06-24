// data/api_client.dart — thin HTTP client for the FastAPI backend. The app is
// local-first; this is only used when the user opts to sync.
//
// Auth model: every per-user route is `/me/...` and reads the user from the JWT
// we send as `Authorization: Bearer <token>`. The client holds the token after
// sign-in; the backend scopes all data to that user.
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => 'ApiException($status): $message';
}

class ApiClient {
  final String baseUrl;
  final http.Client _client;
  String? _token;

  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  bool get isSignedIn => _token != null;

  Map<String, String> _headers([Map<String, String>? extra]) => {
        if (_token != null) 'Authorization': 'Bearer $_token',
        ...?extra,
      };

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
    _token = (jsonDecode(r.body) as Map<String, dynamic>)['access_token'] as String;
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
}
