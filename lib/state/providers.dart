// state/providers.dart — Riverpod wiring. Exposes the logs and the derived
// ranks (computed by the validated engine) to the UI. Chosen for clean,
// testable, dependency-injected state that maps well from the prototype's bus.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repository.dart';
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log;

final repositoryProvider =
    Provider<Repository>((ref) => InMemoryRepository().seedDemo());

/// All logs, keyed by metric id. Mutations go through the notifier.
final logsProvider =
    StateNotifierProvider<LogsNotifier, Map<String, List<Log>>>((ref) {
  return LogsNotifier(ref.watch(repositoryProvider));
});

class LogsNotifier extends StateNotifier<Map<String, List<Log>>> {
  final Repository repo;
  LogsNotifier(this.repo) : super(repo.loadLogs());

  void add(String metricId, Log log) {
    repo.saveLog(metricId, log);
    state = repo.loadLogs();
  }

  void remove(String metricId, int index) {
    repo.deleteLog(metricId, index);
    state = repo.loadLogs();
  }
}

/// Latest logged bodyweight, used to PRE-FILL new strength logs. The value
/// snapshotted onto each lift is then fixed forever (bodyweight-at-time).
final currentBodyweightProvider = Provider<double?>((ref) {
  final logs = ref.watch(logsProvider);
  final bw = logs['bodyweight'];
  return (bw != null && bw.isNotEmpty) ? bw.last.value : null;
});

/// Latest log per metric (the value that currently counts).
final latestLogsProvider = Provider<Map<String, Log>>((ref) {
  final logs = ref.watch(logsProvider);
  return {
    for (final e in logs.entries)
      if (e.value.isNotEmpty) e.key: e.value.last
  };
});

/// Overall rank — latest ranked lifts, each scored at its own snapshot weight.
final overallProvider = Provider<eng.RankResult>((ref) {
  final latest = ref.watch(latestLogsProvider);
  final logs = latest.values.where((l) => eng.standards.containsKey(l.metricId));
  return eng.overall(logs.toList());
});

/// Rank for a single metric's latest log (null if never logged).
eng.RankResult? rankFor(WidgetRef ref, String metricId) {
  final latest = ref.watch(latestLogsProvider)[metricId];
  if (latest == null || !eng.standards.containsKey(metricId)) return null;
  return eng.scoreLog(latest);
}
