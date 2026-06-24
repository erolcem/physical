// data/sync.dart — opt-in sync of local logs to the backend canonical store.
// Local-first is preserved: ranks are still computed on-device; this just mirrors
// the same logs up so the backend (and, later, Google Health) share one store.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/rank_engine.dart' show Log;
import '../state/providers.dart';
import 'api_client.dart';
import 'repository.dart';

// Backend URL. Defaults to localhost for dev; point a real build at the hosted
// server with:  flutter build ... --dart-define=BACKEND_URL=https://your-host
const String kBackendUrl =
    String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000');
const String kLocalUserId = 'local-dev'; // only used by the dev sign-in path

final apiClientProvider =
    Provider<ApiClient>((ref) => ApiClient(baseUrl: kBackendUrl));

/// One local log → one canonical sample. `source_id` is stable per (metric, ts)
/// so re-syncing the same log is idempotent (the backend dedups on
/// user+metric+source+source_id).
Map<String, dynamic> canonicalSample(Log log) => {
      'metric_id': log.metricId,
      'ts': log.ts,
      'value': log.value,
      'bodyweight_at_ts': log.bodyweight,
      'source': 'manual',
      'source_id': '${log.metricId}@${log.ts}',
    };

class SyncResult {
  final int total, ingested, skipped;
  final String? backendOverall; // e.g. "Gold II", for parity display
  SyncResult(this.total, this.ingested, this.skipped, this.backendOverall);
}

/// Pure: push all logs, then read back the server's overall rank. No Riverpod,
/// so it's unit-testable with a fake [ApiClient]. (Caller signs in first.)
Future<SyncResult> performSync(ApiClient api, Map<String, List<Log>> logs) async {
  final samples = [
    for (final list in logs.values)
      for (final log in list) canonicalSample(log)
  ];
  final res = await api.ingestSamples(samples);
  String? overall;
  try {
    final ranks = await api.fetchRanks();
    final o = ranks['overall'] as Map<String, dynamic>?;
    if (o != null) overall = '${o['tier']} ${o['sub']}';
  } catch (_) {
    // ranks are a nice-to-have for the confirmation message; ignore failures.
  }
  return SyncResult(samples.length, (res['ingested'] ?? 0) as int,
      (res['skipped'] ?? 0) as int, overall);
}

/// UI entry point: sync the current local logs (caller must be signed in).
Future<SyncResult> syncNow(WidgetRef ref) async {
  final api = ref.read(apiClientProvider);
  await api.loadPersistedToken();
  return performSync(api, ref.read(logsProvider));
}

// ── Pull (backend → app) ────────────────────────────────────────────────────

/// Merge backend samples into [repo], skipping any already present (dedupe by
/// metric + timestamp). Returns how many were newly added. Pure & testable.
int mergeSamples(Repository repo, List<Map<String, dynamic>> samples) {
  final existing = repo.loadLogs();
  var added = 0;
  for (final s in samples) {
    final mid = s['metric_id'] as String;
    final ts = s['ts'] as String;
    final list = existing[mid] ??= <Log>[];
    if (list.any((l) => l.ts == ts)) continue; // already have this day's value
    final log = Log(mid, (s['value'] as num).toDouble(),
        bodyweight: (s['bodyweight_at_ts'] as num?)?.toDouble(), ts: ts);
    repo.saveLog(mid, log);
    list.add(log); // keep the snapshot current for in-batch dedupe
    added++;
  }
  return added;
}

class CloudSyncResult {
  final int pulled;
  final String note; // short status for the Google leg
  CloudSyncResult(this.pulled, this.note);
}

/// Button action: ask the backend to refresh from Google (best effort), then
/// pull the Google samples down into the local store and refresh the UI.
Future<CloudSyncResult> cloudSync(WidgetRef ref) async {
  final api = ref.read(apiClientProvider);
  final repo = ref.read(repositoryProvider);
  await api.loadPersistedToken();

  String note;
  try {
    final g = await api.triggerGoogleSync();
    final errs = (g['errors'] as Map?) ?? const {};
    note = errs.isEmpty ? 'Google +${g['ingested']}' : 'Google: reconnect needed';
  } catch (_) {
    note = 'Google refresh skipped';
  }

  final samples = await api.fetchSamples(source: 'google_health');
  final added = mergeSamples(repo, samples);
  ref.read(logsProvider.notifier).reload();
  return CloudSyncResult(added, note);
}
