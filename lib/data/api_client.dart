// data/api_client.dart — thin HTTP client for the FastAPI backend. The app is
// local-first; this is only used when the user opts to sync. Nothing here is on
// the critical path of computing/showing ranks locally.
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
  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

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

  /// Bulk-ingest canonical samples. Returns {ingested, skipped, ids}.
  Future<Map<String, dynamic>> ingestSamples(
      String userId, List<Map<String, dynamic>> samples) async {
    final r = await _client
        .post(
          Uri.parse('$baseUrl/users/$userId/samples'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(samples),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw ApiException('ingest failed: ${r.body}', r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Overall + per-category + per-metric ranks computed server-side.
  Future<Map<String, dynamic>> fetchRanks(String userId) async {
    final r = await _client
        .get(Uri.parse('$baseUrl/users/$userId/ranks'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw ApiException('ranks failed: ${r.body}', r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Canonical samples for a user, optionally filtered by source/metric.
  Future<List<Map<String, dynamic>>> fetchSamples(String userId,
      {String? source, String? metricId, int limit = 2000}) async {
    final uri = Uri.parse('$baseUrl/users/$userId/samples').replace(
      queryParameters: {
        'limit': '$limit',
        if (source != null) 'source': source,
        if (metricId != null) 'metric_id': metricId,
      },
    );
    final r = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw ApiException('fetch samples failed: ${r.body}', r.statusCode);
    }
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  /// Ask the backend to pull fresh data from Google Health. Best-effort: returns
  /// the result map (may contain an `errors` map if tokens expired).
  Future<Map<String, dynamic>> triggerGoogleSync(String userId,
      {int days = 7}) async {
    final r = await _client
        .post(Uri.parse('$baseUrl/integrations/google/sync?user_id=$userId&days=$days'))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw ApiException('google sync failed: ${r.body}', r.statusCode);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
