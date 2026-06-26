// ui/exercise_screen.dart — the Exercise section (Progress tab). A title card with
// the last session, week stats + volume trend, and a list of recent sessions. Tap a
// session → its detail with grouped sets + stats; add sets of any free-text exercise
// in a locked mode (weight×reps · reps · time · distance). Decoupled from ranks; feeds
// the coach + habit verification.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sync.dart' show apiClientProvider;
import '../data/workout.dart';
import '../state/log_providers.dart';

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
const _teal = Color(0xFF4CE0C3);
const _muted = Color(0xFF7880A8);

void openExerciseScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExerciseScreen()));
}

String _shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : '${d.day}/${d.month}';
}

/// The stat chips to show for a session — duration + (for Google sessions) the cardio
/// summary, plus sets/volume when present.
List<(String, String)> sessionStats(WorkoutSession s) {
  final out = <(String, String)>[];
  if (s.durationMins != null) out.add(('${s.durationMins}m', 'duration'));
  if (s.fromGoogle) {
    final cal = s.summary['calories'], dist = s.summary['distance_km'], hr = s.summary['avg_hr'];
    if (cal != null) out.add(('${cal.round()}', 'kcal'));
    if (dist != null && dist > 0) out.add((dist.toStringAsFixed(2), 'km'));
    if (hr != null) out.add(('${hr.round()}', 'avg hr'));
    if ((s.zoneMinutes ?? 0) > 0) out.add(('${s.zoneMinutes}', 'zone min'));
  }
  if (s.setCount > 0) out.add(('${s.setCount}', 'sets'));
  if (s.volume > 0) out.add(('${s.volume.round()}', 'volume'));
  if (out.isEmpty) out.add(('${s.setCount}', 'sets'));
  return out;
}

class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({super.key});
  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncGoogle());
  }

  // Pull recent Google exercise sessions and import the new ones (dedup by id).
  Future<void> _syncGoogle() async {
    final api = ref.read(apiClientProvider);
    setState(() => _syncing = true);
    try {
      await api.loadPersistedToken();
      if (api.isSignedIn) {
        final sessions = await api.googleExercises();
        final added = ref.read(workoutProvider.notifier).importGoogle(sessions);
        if (added > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Imported $added Google workout${added == 1 ? '' : 's'}'),
              duration: const Duration(seconds: 2)));
        }
      }
    } catch (_) {/* offline / not signed in — manual still works */}
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = sortedByRecent(ref.watch(workoutProvider));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Exercise'),
        actions: [
          _syncing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: 'Import Google workouts',
                  icon: const Icon(Icons.cloud_download_outlined),
                  onPressed: _syncGoogle),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        onPressed: _newSession,
        icon: const Icon(Icons.add),
        label: const Text('New workout'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        if (sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('No workouts yet — start one, or import from Google (☁).',
                style: TextStyle(color: _muted))))
        else ...[
          _lastCard(sessions.first),
          const SizedBox(height: 12),
          _weekStats(sessions),
          const SizedBox(height: 16),
          const Text('RECENT', style: TextStyle(fontSize: 11, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 6),
          for (final s in sessions.take(30)) _sessionRow(context, s),
        ],
      ]),
    );
  }

  Widget _lastCard(WorkoutSession s) => Card(
        color: _card,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('LAST WORKOUT', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const SizedBox(height: 8),
            Row(children: [
              Text(typeEmoji(s.type), style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  Text('${s.type} · ${_shortDate(s.start)}${s.fromGoogle ? ' · ☁ Google' : ''}',
                      style: const TextStyle(fontSize: 12, color: _muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [for (final (v, l) in sessionStats(s).take(4)) _stat(v, l)]),
          ]),
        ),
      );

  Widget _weekStats(List<WorkoutSession> sessions) {
    final perDay = volumePerDay(sessions, days: 7);
    final maxV = perDay.fold<double>(1, (m, v) => v > m ? v : m);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LAST 7 DAYS', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < perDay.length; i++)
                Container(width: 22, height: 4 + 40 * (perDay[i] / maxV),
                    decoration: BoxDecoration(
                        color: i == perDay.length - 1 ? _teal : _teal.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4))),
            ],
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat('${sessionsOverDays(sessions, days: 7)}', 'sessions'),
            _stat('${volumeOverDays(sessions, days: 7).round()}', 'volume'),
            _stat('${exercisesOverDays(sessions, days: 7).length}', 'exercises'),
          ]),
        ]),
      ),
    );
  }

  Widget _stat(String v, String l) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _teal)),
        const SizedBox(height: 2),
        Text(l, style: const TextStyle(fontSize: 10, color: _muted)),
      ]);

  Widget _sessionRow(BuildContext context, WorkoutSession s) => Card(
        color: _card,
        child: ListTile(
          leading: Text(typeEmoji(s.type), style: const TextStyle(fontSize: 24)),
          title: Row(children: [
            Flexible(child: Text(s.label, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700))),
            if (s.fromGoogle)
              const Padding(padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.cloud, size: 13, color: _muted)),
          ]),
          subtitle: Text(
              '${_shortDate(s.start)} · ${sessionStats(s).map((e) => '${e.$1} ${e.$2}').take(3).join(' · ')}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          trailing: const Icon(Icons.chevron_right, color: _muted),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SessionDetailScreen(sessionId: s.id))),
        ),
      );

  Future<void> _newSession() async {
    var type = sessionTypes.first.$1;
    final title = TextEditingController();
    final dur = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _card,
          title: const Text('New workout'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Type', style: TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in sessionTypes)
                  ChoiceChip(
                    label: Text('${t.$2} ${t.$1}', style: const TextStyle(fontSize: 12)),
                    selected: type == t.$1,
                    onSelected: (_) => setLocal(() => type = t.$1),
                    selectedColor: _accent.withValues(alpha: 0.25),
                    backgroundColor: _bg,
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(
                  labelText: 'Title (optional)', hintText: 'e.g. Push day', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: dur, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duration mins (optional)', border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;
    final s = ref.read(workoutProvider.notifier).createSession(
          type: type,
          title: title.text.trim().isEmpty ? null : title.text.trim(),
          durationMins: int.tryParse(dur.text),
        );
    if (!mounted) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SessionDetailScreen(sessionId: s.id)));
  }
}

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  const SessionDetailScreen({required this.sessionId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(workoutProvider).where((x) => x.id == sessionId).firstOrNull;
    if (s == null) {
      return const Scaffold(backgroundColor: _bg, body: Center(child: Text('Workout removed', style: TextStyle(color: _muted))));
    }
    final grouped = groupByExercise(s.sets);
    // Original indices for delete, keyed by identity order.
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(s.label),
        actions: [
          IconButton(
            tooltip: 'Delete workout',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              ref.read(workoutProvider.notifier).remove(s.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        onPressed: () => _addSet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add set'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        _header(s),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 20, runSpacing: 12,
          children: [for (final (v, l) in sessionStats(s)) _stat(v, l)],
        ),
        const SizedBox(height: 16),
        if (s.sets.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No sets yet — add one below.', style: TextStyle(color: _muted))))
        else
          for (final e in grouped.entries) _exerciseBlock(ref, s, e.key, e.value),
      ]),
    );
  }

  Widget _header(WorkoutSession s) => Card(
        color: _card,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(typeEmoji(s.type), style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text(
                    '${s.type} · ${_shortDate(s.start)}'
                    '${s.fromGoogle ? ' · ☁ from Google' : ''}',
                    style: const TextStyle(fontSize: 12, color: _muted)),
              ]),
            ),
          ]),
        ),
      );

  Widget _stat(String v, String l) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _teal)),
        const SizedBox(height: 2),
        Text(l, style: const TextStyle(fontSize: 10, color: _muted)),
      ]);

  Widget _exerciseBlock(WidgetRef ref, WorkoutSession s, String name, List<WorkoutSet> sets) => Card(
        color: _card,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            for (final set in sets)
              Row(children: [
                const Text('•  ', style: TextStyle(color: _muted)),
                Expanded(child: Text(set.detail, style: const TextStyle(fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: _muted),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref.read(workoutProvider.notifier).removeSet(s.id, s.sets.indexOf(set)),
                ),
              ]),
          ]),
        ),
      );

  Future<void> _addSet(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    var mode = SetMode.weightReps;
    final weight = TextEditingController();
    final reps = TextEditingController();
    final mins = TextEditingController();
    final secs = TextEditingController();
    final dist = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget num(TextEditingController c, String label) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
                  ),
                ),
              );
          return AlertDialog(
            backgroundColor: _card,
            title: const Text('Add set'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: name, autofocus: true, decoration: const InputDecoration(
                    labelText: 'Exercise', hintText: 'e.g. Chest Press', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                const Text('Mode', style: TextStyle(fontSize: 11, color: _muted)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final m in SetMode.values)
                    ChoiceChip(
                      label: Text(m.label, style: const TextStyle(fontSize: 12)),
                      selected: mode == m,
                      onSelected: (_) => setLocal(() => mode = m),
                      selectedColor: _accent.withValues(alpha: 0.25),
                      backgroundColor: _bg,
                    ),
                ]),
                const SizedBox(height: 12),
                if (mode == SetMode.weightReps)
                  Row(children: [num(weight, 'Weight (kg)'), num(reps, 'Reps')])
                else if (mode == SetMode.reps)
                  Row(children: [num(reps, 'Reps')])
                else if (mode == SetMode.time)
                  Row(children: [num(mins, 'Minutes'), num(secs, 'Seconds')])
                else
                  Row(children: [num(dist, 'Distance (km)')]),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) return;
    final set = WorkoutSet(
      name: name.text.trim(),
      mode: mode,
      weight: double.tryParse(weight.text),
      reps: int.tryParse(reps.text),
      seconds: mode == SetMode.time
          ? (double.tryParse(mins.text) ?? 0) * 60 + (double.tryParse(secs.text) ?? 0)
          : null,
      distance: double.tryParse(dist.text),
    );
    ref.read(workoutProvider.notifier).addSet(sessionId, set);
  }
}
