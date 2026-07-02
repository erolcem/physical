// data/sync.dart — opt-in sync of local logs to the backend canonical store.
// Local-first is preserved: ranks are still computed on-device; this just mirrors
// the same logs up so the backend (and, later, Google Health) share one store.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../engine/rank_engine.dart' show Log;
import '../state/habit_providers.dart' show habitsProvider;
import '../state/log_providers.dart' show dietProvider, workoutProvider, pinsProvider;
import '../state/providers.dart';
import 'ai_verify.dart' show runAiVerification;
import 'api_client.dart';
import 'coach_context.dart' show coachHabits, coachRanks, coachTrends;
import 'notifications.dart' show NotificationService;
import 'rank_history.dart' show backfillRankLogs, resetDerivedHistory;
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

/// Merge backend samples into [repo]: new (metric, timestamp) pairs are added,
/// and an existing pair whose VALUE changed server-side (today's step total
/// grows through the day; vendor-revised sleep scores) is updated in place —
/// otherwise local history freezes at whatever the first sync saw. Returns how
/// many were added or updated. Pure & testable.
int mergeSamples(Repository repo, List<Map<String, dynamic>> samples) {
  final existing = repo.loadLogs();
  final tombs = repo.loadTombstones();
  var changed = 0;
  for (final s in samples) {
    final mid = s['metric_id'] as String;
    final ts = s['ts'] as String;
    if (tombs.contains('$mid@$ts')) continue; // deleted locally — don't let Google re-add it
    final value = (s['value'] as num).toDouble();
    final list = existing[mid] ??= <Log>[];
    final i = list.indexWhere((l) => l.ts == ts);
    if (i >= 0) {
      if ((list[i].value - value).abs() > 1e-9) {
        final log = Log(mid, value, bodyweight: list[i].bodyweight, ts: ts);
        repo.replaceLog(mid, i, log);
        list[i] = log;
        changed++;
      }
      continue;
    }
    final log = Log(mid, value,
        bodyweight: (s['bodyweight_at_ts'] as num?)?.toDouble(), ts: ts);
    repo.saveLog(mid, log);
    list.add(log); // keep the snapshot current for in-batch dedupe
    changed++;
  }
  return changed;
}

class CloudSyncResult {
  final int pulled;
  final String note; // short status for the Google leg
  final bool needsReconnect; // the Google Health token expired (7-day testing limit)
  final bool calendarNeedsReconnect; // habits couldn't write to Calendar (scope not granted)
  CloudSyncResult(this.pulled, this.note,
      {this.needsReconnect = false, this.calendarNeedsReconnect = false});
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
    final errs = ((g['errors'] as Map?) ?? const {}).cast<String, dynamic>();
    // The backend classifies auth failures: 'token' = refresh expired, 'scope' =
    // stale token predating a new permission (both fixed by a one-tap reconnect);
    // 'grant' = the LAST consent didn't grant the health scopes (reconnect AND
    // tick every checkbox / fix the consent screen); 'api_disabled' = the Google
    // Health API is off in the Cloud project (console fix, not a reconnect).
    if (errs.containsKey('api_disabled')) {
      note = 'Google Health API is disabled in your Cloud project — enable it in the console';
    } else if (errs.containsKey('grant')) {
      needsReconnect = true;
      note = 'Google didn\'t grant health access — reconnect and tick every checkbox';
    } else if (errs.containsKey('token') || errs.containsKey('scope')) {
      needsReconnect = true;
      note = 'Google sign-in expired';
    } else if (errs.isEmpty) {
      note = 'Google +${g['ingested']}';
    } else {
      // Name what failed instead of a blanket "partial sync" — the data that
      // works still synced fine.
      final failed = errs.keys.take(3).join(', ');
      note = 'Google +${g['ingested']} · $failed unavailable';
    }
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
  // Mirror habits into Google Calendar automatically (idempotent upsert). Awaited so we
  // know if it needs the calendar scope (then we can prompt a reconnect).
  var calendarNeedsReconnect = false;
  try {
    final habits = [for (final h in ref.read(habitsProvider).habits) h.toJson()];
    if (habits.isNotEmpty) {
      String? tzName;
      try {
        tzName = await FlutterTimezone.getLocalTimezone();
      } catch (_) {/* floating times */}
      try {
        await api.pushCalendar(habits, tzName);
      } on ApiException catch (e) {
        if (e.status == 401 || e.status == 403) calendarNeedsReconnect = true;
      }
    }
  } catch (_) {/* calendar mirror is best-effort */}
  // The daily AI loop (item 15), in order and off the critical path:
  //   1. VERIFY — the LLM re-judges today's non-manual habits against the day's
  //      real evidence (robust to custom habits; one workout can't tick two).
  //   2. NUDGES — the morning brief (8am, day ahead) and the evening digest
  //      (8pm, how today went) are regenerated from the live context, with the
  //      evening one scheduled AFTER verification so it reflects the verdicts.
  // All best-effort; the rule-based checks remain the fallback.
  unawaited(() async {
    int? judged;
    try {
      judged = await runAiVerification(api, repo);
    } catch (_) {/* verification is best-effort */}
    if (judged != null && judged > 0) ref.invalidate(habitsProvider);
    try {
      final logs = ref.read(logsProvider);
      final hs = ref.read(habitsProvider);
      final habitsCtx = coachHabits(hs.habits, hs.completions,
          logs: logs, food: ref.read(dietProvider), workouts: ref.read(workoutProvider),
          aiVerdicts: hs.aiVerdicts);
      final ranksCtx = ref.read(latestLogsProvider).isEmpty
          ? null
          : coachRanks(
              overall: ref.read(overallProvider),
              categories: ref.read(categoryRanksProvider),
              latest: ref.read(latestLogsProvider),
              logs: logs);
      final trendsCtx = coachTrends(logs);
      Future<void> sched(String slot, int id, int hour) async {
        final n = await api.coachNudge(slot: slot, habits: habitsCtx, ranks: ranksCtx, trends: trendsCtx);
        if (n != null) await NotificationService.instance.scheduleAiNudge(id, n, hour);
      }
      unawaited(sched('morning', NotificationService.nudgeMorningId, 8));
      unawaited(sched('evening', NotificationService.nudgeEveningId, 20));
    } catch (_) {/* nudges are best-effort */}
  }());
  return CloudSyncResult(added, note,
      needsReconnect: needsReconnect, calendarNeedsReconnect: calendarNeedsReconnect);
}

/// Rebuild the derived rank/readiness history purely from the data that exists
/// NOW (item: deleting data used to leave the old category-rank climb behind),
/// then refresh the graphs. Returns how many day-points were rebuilt.
int recomputeDerivedHistory(WidgetRef ref) {
  final repo = ref.read(repositoryProvider);
  final n = resetDerivedHistory(repo, readinessBackfill: backfillReadinessLogs);
  ref.read(logsProvider.notifier).reload();
  return n;
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
