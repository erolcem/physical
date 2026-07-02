// Sync layer: canonical serialization + performSync, using a fake ApiClient
// (no network). The live app↔backend round-trip is verified separately.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/api_client.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/sync.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

class _FakeApi extends ApiClient {
  List<Map<String, dynamic>>? sent;
  _FakeApi() : super(baseUrl: 'http://test');

  @override
  Future<Map<String, dynamic>> ingestSamples(
      List<Map<String, dynamic>> samples) async {
    sent = samples;
    return {'ingested': samples.length, 'skipped': 0, 'ids': []};
  }

  @override
  Future<Map<String, dynamic>> fetchRanks() async => {
        'overall': {'tier': 'Gold', 'sub': 'II', 'top_pct': 30.0, 'rank_value': 3.5},
        'categories': {},
        'metrics': {},
      };
}

void main() {
  test('canonicalSample maps a log to the backend schema', () {
    final s = canonicalSample(
        Log('bench', 100, bodyweight: 80, ts: '2026-06-01T08:00:00.000'));
    expect(s['metric_id'], 'bench');
    expect(s['value'], 100);
    expect(s['bodyweight_at_ts'], 80);
    expect(s['source'], 'manual');
    expect(s['ts'], '2026-06-01T08:00:00.000');
    // Stable per (metric, ts) ⇒ re-syncing the same log is idempotent.
    expect(s['source_id'], 'bench@2026-06-01T08:00:00.000');
  });

  test('mergeSamples adds backend samples and dedupes by metric+ts', () {
    final repo = InMemoryRepository();
    final samples = [
      {'metric_id': 'resting_hr', 'ts': '2026-06-24T00:00:00', 'value': 50.0,
       'bodyweight_at_ts': null, 'source': 'google_health'},
      {'metric_id': 'hrv', 'ts': '2026-06-24T00:00:00', 'value': 122.05,
       'bodyweight_at_ts': null, 'source': 'google_health'},
    ];
    expect(mergeSamples(repo, samples), 2);
    expect(repo.loadLogs()['resting_hr']!.single.value, 50.0);
    expect(repo.loadLogs()['hrv']!.single.value, 122.05);
    // Re-merging the same data adds nothing (idempotent).
    expect(mergeSamples(repo, samples), 0);
    expect(repo.loadLogs()['resting_hr']!.length, 1);
  });

  test('mergeSamples updates a revised value in place (same metric+ts)', () {
    // Today's step total grows through the day — the same (metric, ts) sample
    // arrives with a larger value on the next sync and must replace, not freeze.
    final repo = InMemoryRepository();
    expect(mergeSamples(repo, [
      {'metric_id': 'steps', 'ts': '2026-06-24T00:00:00', 'value': 3000.0,
       'bodyweight_at_ts': null, 'source': 'google_health'},
    ]), 1);
    expect(mergeSamples(repo, [
      {'metric_id': 'steps', 'ts': '2026-06-24T00:00:00', 'value': 9500.0,
       'bodyweight_at_ts': null, 'source': 'google_health'},
    ]), 1);
    final logs = repo.loadLogs()['steps']!;
    expect(logs.length, 1); // replaced, not duplicated
    expect(logs.single.value, 9500.0);
  });

  test('performSync flattens all logs and reports the backend overall', () async {
    final api = _FakeApi();
    final logs = {
      'bench': [
        Log('bench', 100, bodyweight: 80, ts: 't1'),
        Log('bench', 110, bodyweight: 80, ts: 't2'),
      ],
      'vo2max': [Log('vo2max', 50, ts: 't3')],
    };
    final r = await performSync(api, logs);
    expect(r.total, 3);
    expect(r.ingested, 3);
    expect(api.sent!.length, 3);
    expect(r.backendOverall, 'Gold II');
  });
}
