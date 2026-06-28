// data/sync.dart — opt-in sync of local logs to the backend canonical store.
// Local-first is preserved: ranks are still computed on-device; this just mirrors
// the same logs up so the backend (and, later, Google Health) share one store.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/rank_engine.dart' show Log;
import '../state/habit_providers.dart' show habitsProvider;
import '../state/log_providers.dart' show dietProvider, workoutProvider, pinsProvider;
import '../state/providers.dart';
import 'api_client.dart';
import 'rank_history.dart' show backfillRankLogs;
import 'readiness.dart' show backfillReadinessLogs;
import 'repository.dart';

// Backend URL. Defaults to the hosted Railway backend so a plain `flutter run`
// (and the iPhone build) sync with zero config. For local backend development,
// override it:  flutter run ... --dart-define=BACKEND_URL=http://localhost:8000
const String kBackendUrl = String.fromEnvironment('BACKEND_URL',
    defaultValue: 'https://physical-production-883c.up.railway.app');
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
  final tombs = repo.loadTombstones();
  var added = 0;
  for (final s in samples) {
    final mid = s['metric_id'] as String;
    final ts = s['ts'] as String;
    if (tombs.contains('$mid@$ts')) continue; // deleted locally — don't let Google re-add it
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
  final bool needsReconnect; // the Google Health token expired (7-day testing limit)
  CloudSyncResult(this.pulled, this.note, {this.needsReconnect = false});
}

/// Button action: ask the backend to refresh from Google (best effort), then
/// pull the Google samples down into the local store and refresh the UI.
Future<CloudSyncResult> cloudSync(WidgetRef ref) async {
  final api = ref.read(apiClientProvider);
  final repo = ref.read(repositoryProvider);
  await api.loadPersistedToken();

  String note;
  var needsReconnect = false;
  try {
    final g = await api.triggerGoogleSync();
    final errs = (g['errors'] as Map?) ?? const {};
    // A 'token' error means the Google Health refresh token expired — the user
    // just needs to sign in with Google again (refreshes it).
    needsReconnect = errs.containsKey('token');
    note = errs.isEmpty
        ? 'Google +${g['ingested']}'
        : (needsReconnect ? 'Google sign-in expired' : 'Google: partial sync');
  } catch (_) {
    note = 'Google refresh skipped';
  }

  final samples = await api.fetchSamples(source: 'google_health');
  final added = mergeSamples(repo, samples);
  backfillReadinessLogs(repo); // recompute readiness now that recovery data updated
  backfillRankLogs(repo); // log today's overall + category ranks for the rank graphs
  ref.read(logsProvider.notifier).reload();
  // Google Health food logs (nutrition-log) → the Diet section, deduped by id; then
  // ask the AI to fill the diet-health radar for foods that lack health axes.
  try {
    ref.read(dietProvider.notifier).importGoogle(await api.googleFoods());
    // Background: fill the diet-health radar via the AI (many calls) without blocking
    // the sync. Refresh the Diet UI when it finishes — the enrichment can outlive the
    // dietProvider invalidate below, so re-read the freshly-enriched repo at the end.
    unawaited(ref.read(dietProvider.notifier).enrichFoodHealth(api).then((n) {
      if (n > 0) ref.invalidate(dietProvider);
    }).catchError((_) {}));
  } catch (_) {/* food import + enrichment are best-effort */}
  // Full-data sync: MERGE the cloud snapshot into local (so the other device's data
  // arrives without clobbering), then push the merged result back. Both devices
  // converge over syncs — no last-write-wins data loss. Best-effort.
  try {
    final cloud = await api.pullBackup();
    if (cloud != null) {
      repoMerge(repo, cloud);
      ref.read(logsProvider.notifier).reload();
      ref.invalidate(dietProvider);
      ref.invalidate(workoutProvider);
      ref.invalidate(habitsProvider);
      ref.invalidate(pinsProvider);
    }
    await api.pushBackup(repoExport(repo));
  } catch (_) {/* backup is best-effort */}
  return CloudSyncResult(added, note, needsReconnect: needsReconnect);
}

/// Pull the cloud snapshot and REPLACE all local data with it (new-device restore).
/// Returns true if a backup existed and was restored. Reloads every data provider.
Future<bool> restoreFromCloud(WidgetRef ref) async {
  final api = ref.read(apiClientProvider);
  final repo = ref.read(repositoryProvider);
  await api.loadPersistedToken();
  final snapshot = await api.pullBackup();
  if (snapshot == null) return false;
  repoImport(repo, snapshot);
  // Re-read every provider from the freshly-restored repo.
  ref.read(logsProvider.notifier).reload();
  ref.invalidate(dietProvider);
  ref.invalidate(workoutProvider);
  ref.invalidate(habitsProvider);
  ref.invalidate(pinsProvider);
  return true;
}
