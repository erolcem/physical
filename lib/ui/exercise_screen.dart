// ui/exercise_screen.dart — the Exercise section (Progress tab). A title card with
// the last session, week stats + volume trend, and a list of recent sessions. Tap a
// session → its detail with grouped sets + stats; add sets of any free-text exercise
// in a locked mode (weight×reps · reps · time · distance). Decoupled from ranks; feeds
// the coach + habit verification.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/habits.dart' show isDueOn, todayKey;
import '../data/metrics.dart' show MetricDef, MetricTier;
import '../data/sync.dart' show apiClientProvider;
import '../data/workout.dart';
import '../engine/rank_engine.dart' show Log;
import '../state/habit_providers.dart';
import '../state/log_providers.dart';
import 'progress_screen.dart' show GraphArea;

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

/// Watch-anchoring badge: sets only "count" when the session is (or is linked
/// to) a real tracked watch exercise — unverified = self-reported typing.
Widget watchBadge(WorkoutSession s) => s.watchVerified
    ? const Text('✓ watch', style: TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w700))
    : const Text('⚠ unverified',
        style: TextStyle(fontSize: 11, color: Color(0xFFF6CF3E), fontWeight: FontWeight.w700));

/// The stat chips to show for a session — duration + (for Google sessions) the cardio
/// summary, plus sets/volume when present.
List<(String, String)> sessionStats(WorkoutSession s) {
  final out = <(String, String)>[];
  if (s.durationMins != null) out.add(('${s.durationMins}m', 'duration'));
  if (s.fromGoogle) {
    final cal = s.summary['calories'], dist = s.summary['distance_km'], hr = s.summary['avg_hr'];
    if ((s.cardioLoad ?? 0) > 0) out.add(('${s.cardioLoad!.round()}', 'cardio load'));
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
    final all = sortedByRecent(ref.watch(workoutProvider));
    // Fresh unverified holders wait for their watch exercise in their own strip —
    // they're pre-logged sets, not workouts of their own. Older unverified ones
    // stay in RECENT with the ⚠ badge (history is history).
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    final pending = [
      for (final s in all)
        if (!s.watchVerified && (DateTime.tryParse(s.start)?.isAfter(cutoff) ?? false)) s
    ];
    final sessions = [for (final s in all) if (!pending.contains(s)) s];
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
        onPressed: _logSets,
        icon: const Icon(Icons.add),
        label: const Text('Log sets'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        _todaysPlan(),
        _templatesRow(),
        if (pending.isNotEmpty) _pendingSection(pending),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('No workouts yet — track one with your watch and import (☁), '
                'or pre-log sets with +.',
                style: TextStyle(color: _muted))))
        else if (sessions.isNotEmpty) ...[
          _lastCard(sessions.first),
          const SizedBox(height: 12),
          const _ExerciseMetricGraph(),
          const SizedBox(height: 16),
          Text('RECENT · ${sessions.length}', style: const TextStyle(fontSize: 11, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 6),
          // Short lists inline; long ones scroll inside a fixed window so the page
          // never grows unbounded (scales to thousands of sessions).
          if (sessions.length <= 12)
            for (final s in sessions) _sessionRow(context, s)
          else
            SizedBox(
              height: 460,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: sessions.length,
                itemBuilder: (_, i) => _sessionRow(context, sessions[i]),
              ),
            ),
        ],
      ]),
    );
  }

  // ── Pre-logged sets waiting for their tracked exercise (holders, not workouts).
  // They attach automatically the moment the covering watch session syncs in. ──
  Widget _pendingSection(List<WorkoutSession> pending) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('WAITING FOR THE WATCH EXERCISE',
              style: TextStyle(fontSize: 11, letterSpacing: 2, color: Color(0xFFF6CF3E))),
          const SizedBox(height: 6),
          for (final s in pending)
            Card(
              color: _card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0x33F6CF3E)),
              ),
              child: ListTile(
                leading: const Icon(Icons.hourglass_top, color: Color(0xFFF6CF3E), size: 22),
                title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${s.setCount} sets pre-logged · attaches to your tracked '
                    'exercise on the next sync',
                    style: const TextStyle(fontSize: 11.5, color: _muted)),
                trailing: const Icon(Icons.chevron_right, color: _muted),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(sessionId: s.id))),
              ),
            ),
        ]),
      );

  // ── Today's plan: exercise habits due today that carry a workout plan — the
  // habit is the plan, tapping starts the session pre-filled. ──
  Widget _todaysPlan() {
    final habits = ref.watch(habitsProvider).habits;
    final templates = {for (final t in ref.watch(templatesProvider)) t.id: t};
    final sessions = ref.watch(workoutProvider);
    final today = DateTime.now();
    final planned = [
      for (final h in habits)
        if (h.section == 'exercise' && h.templateId != null &&
            templates.containsKey(h.templateId) && isDueOn(h, today))
          h
    ];
    if (planned.isEmpty) return const SizedBox.shrink();
    // "Done" here = a session started from this plan exists today (title match).
    final todaysTitles = {
      for (final s in sessions) if (s.dateKey == todayKey()) s.label
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("TODAY'S PLAN", style: TextStyle(fontSize: 11, letterSpacing: 2, color: _muted)),
        const SizedBox(height: 6),
        for (final h in planned)
          () {
            final t = templates[h.templateId]!;
            final done = todaysTitles.contains(t.name) || todaysTitles.contains(h.title);
            return Card(
              color: _card,
              child: ListTile(
                leading: Icon(done ? Icons.check_circle : Icons.play_circle_outline,
                    color: done ? _teal : _accent, size: 28),
                title: Text(h.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? _muted : Colors.white)),
                subtitle: Text(
                    '${t.exercises.length} exercises · ${t.setCount} sets'
                    '${h.time != null ? ' · ${h.time}' : ''}',
                    style: const TextStyle(fontSize: 12, color: _muted)),
                trailing: done ? null : const Text('Start', style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
                onTap: done ? null : () => _startFromTemplate(t),
              ),
            );
          }(),
      ]),
    );
  }

  // ── Templates (Hevy-style fast logging): tap → start a pre-filled workout;
  // long-press → delete. Templates are saved from a session's "Save as template". ──
  Widget _templatesRow() {
    final templates = ref.watch(templatesProvider);
    if (templates.isEmpty) {
      // Always visible: without an empty state the feature is undiscoverable
      // (the save action lives inside a session).
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withValues(alpha: 0.25)),
          ),
          child: const Row(children: [
            Icon(Icons.bookmark_add_outlined, size: 18, color: _accent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Templates: open any workout and tap the 🔖 icon to save its sets — '
                'next time it\'s one tap to start pre-filled.',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('TEMPLATES', style: TextStyle(fontSize: 11, letterSpacing: 2, color: _muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in templates)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _startFromTemplate(t),
              onLongPress: () => _templateMenu(t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accent.withValues(alpha: 0.35)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${typeEmoji(t.type)} ${t.name}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${t.exercises.length} exercises · ${t.setCount} sets',
                      style: const TextStyle(fontSize: 10.5, color: _muted)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }

  void _startFromTemplate(WorkoutTemplate t) {
    final s = ref.read(workoutProvider.notifier).createFromTemplate(t);
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SessionDetailScreen(sessionId: s.id)));
  }

  // Long-press a template chip: start / edit / delete.
  void _templateMenu(WorkoutTemplate t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.play_circle_outline, color: _accent),
            title: Text('Start "${t.name}"'),
            onTap: () {
              Navigator.pop(ctx);
              _startFromTemplate(t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: _teal),
            title: const Text('Edit plan'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TemplateEditorScreen(existing: t)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Color(0xFFFA3737)),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(ctx);
              _deleteTemplate(t);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _deleteTemplate(WorkoutTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Delete template "${t.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) ref.read(templatesProvider.notifier).remove(t.id);
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
            Padding(padding: const EdgeInsets.only(left: 6), child: watchBadge(s)),
          ]),
          subtitle: Text(
              '${_shortDate(s.start)} · ${sessionStats(s).map((e) => '${e.$1} ${e.$2}').take(3).join(' · ')}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          trailing: const Icon(Icons.chevron_right, color: _muted),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SessionDetailScreen(sessionId: s.id))),
        ),
      );

  // ── Log sets: sets are CHILDREN of a tracked exercise. If the watch already
  // recorded one today, sets go straight into it; otherwise the user pre-logs
  // into a holder that auto-attaches when the exercise syncs in. ──
  Future<void> _logSets() async {
    final today = todayKey();
    final watch = [
      for (final s in sortedByRecent(ref.read(workoutProvider)))
        if (s.fromGoogle && s.dateKey == today) s
    ];
    if (watch.isEmpty) {
      await _preLog();
      return;
    }
    if (watch.length == 1) {
      // One tracked exercise today — that IS the workout; go straight in.
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SessionDetailScreen(sessionId: watch.first.id)));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Add sets to which tracked exercise?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          for (final s in watch)
            ListTile(
              leading: Text(typeEmoji(s.type), style: const TextStyle(fontSize: 22)),
              title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  sessionStats(s).map((e) => '${e.$1} ${e.$2}').take(3).join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: _muted)),
              trailing: const Text('✓ watch',
                  style: TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(sessionId: s.id)));
              },
            ),
        ]),
      ),
    );
  }

  // Pre-log sets before the watch exercise has synced: a HOLDER, not a workout —
  // it attaches to the covering tracked exercise automatically and disappears.
  Future<void> _preLog() async {
    var type = sessionTypes.first.$1;
    final title = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Pre-log sets'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'No tracked exercise yet today. Record your workout with the '
                'watch — these sets attach to it automatically when it syncs. '
                'Until then they stay ⚠ unverified and don\'t count for habits.',
                style: TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 12),
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
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pre-log')),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;
    final s = ref.read(workoutProvider.notifier).createSession(
          type: type,
          title: title.text.trim().isEmpty ? null : title.text.trim(),
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
    final all = ref.watch(workoutProvider);
    // Follow the absorption trail: if this holder merged into its watch parent
    // while the screen was open, re-bind to the parent seamlessly — the sets
    // are children of the real exercise, and this screen simply becomes it.
    final s = all.where((x) => x.id == sessionId).firstOrNull ??
        all.where((x) => x.absorbedIds.contains(sessionId)).firstOrNull;
    if (s == null) {
      return const Scaffold(
          backgroundColor: _bg,
          body: Center(
              child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('This workout was removed.',
                textAlign: TextAlign.center, style: TextStyle(color: _muted)),
          )));
    }
    final grouped = groupByExercise(s.sets);
    // Original indices for delete, keyed by identity order.
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(s.label),
        actions: [
          if (s.sets.isNotEmpty)
            IconButton(
              tooltip: 'Save as template',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () => _saveAsTemplate(context, ref, s),
            ),
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
                const SizedBox(height: 2),
                watchBadge(s),
                if (!s.watchVerified)
                  const Text(
                      'No tracked watch exercise covers this window yet — start the '
                      'exercise on your watch; it links up on the next sync.',
                      style: TextStyle(fontSize: 10.5, color: _muted)),
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

  // Save this session's sets as a named template for one-tap future workouts.
  Future<void> _saveAsTemplate(BuildContext context, WidgetRef ref, WorkoutSession s) async {
    final name = TextEditingController(text: s.label);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Save as template'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Template name', hintText: 'e.g. Push day', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    ref.read(templatesProvider.notifier).saveFromSession(s, name.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Template "${name.text.trim()}" saved — start it from the Exercise page.'),
          duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _addSet(BuildContext context, WidgetRef ref) async {
    final set = await promptWorkoutSet(context);
    if (set != null) ref.read(workoutProvider.notifier).addSet(sessionId, set);
  }
}

/// Shared "describe one set" dialog (exercise name + mode + values) — used when
/// logging into a session and when editing a workout plan (template).
Future<WorkoutSet?> promptWorkoutSet(BuildContext context, {String? initialName}) async {
  final name = TextEditingController(text: initialName ?? '');
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
              TextField(controller: name, autofocus: initialName == null, decoration: const InputDecoration(
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
  if (ok != true || name.text.trim().isEmpty) return null;
  return WorkoutSet(
    name: name.text.trim(),
    mode: mode,
    weight: double.tryParse(weight.text),
    reps: int.tryParse(reps.text),
    seconds: mode == SetMode.time
        ? (double.tryParse(mins.text) ?? 0) * 60 + (double.tryParse(secs.text) ?? 0)
        : null,
    distance: double.tryParse(dist.text),
  );
}

/// Workout-plan editor: edit a template's name, type and sets directly (the
/// habit-carried plan). Pops with the saved template's id, so callers (e.g. the
/// habit dialog's "New plan…") can link it.
class TemplateEditorScreen extends ConsumerStatefulWidget {
  final WorkoutTemplate? existing;
  final String? suggestedName;
  const TemplateEditorScreen({this.existing, this.suggestedName, super.key});

  @override
  ConsumerState<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  late final TextEditingController _name = TextEditingController(
      text: widget.existing?.name ?? widget.suggestedName ?? '');
  late String _type = widget.existing?.type ?? 'Weightlifting';
  late final List<WorkoutSet> _sets = List.of(widget.existing?.sets ?? const []);

  void _save() {
    if (_name.text.trim().isEmpty || _sets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Give the plan a name and at least one set.')));
      return;
    }
    final t = WorkoutTemplate(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      type: _type,
      sets: List.of(_sets),
    );
    ref.read(templatesProvider.notifier).save(t);
    Navigator.of(context).pop(t.id);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupByExercise(_sets);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(widget.existing == null ? 'New workout plan' : 'Edit workout plan'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Delete plan',
              icon: const Icon(Icons.delete_outline, color: Color(0xFFFA3737)),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: _card,
                    title: Text('Delete plan "${widget.existing!.name}"?'),
                    content: const Text(
                        'Habits pointing at this plan keep working — they just '
                        'lose the pre-filled sets.',
                        style: TextStyle(fontSize: 13, color: _muted)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  ref.read(templatesProvider.notifier).remove(widget.existing!.id);
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        onPressed: () async {
          final s = await promptWorkoutSet(context);
          if (s != null) setState(() => _sets.add(s));
        },
        icon: const Icon(Icons.add),
        label: const Text('Add set'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
              labelText: 'Plan name', hintText: 'e.g. Push day', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        const Text('Type', style: TextStyle(fontSize: 11, color: _muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in sessionTypes)
            ChoiceChip(
              label: Text('${t.$2} ${t.$1}', style: const TextStyle(fontSize: 12)),
              selected: _type == t.$1,
              onSelected: (_) => setState(() => _type = t.$1),
              selectedColor: _accent.withValues(alpha: 0.25),
              backgroundColor: _card,
            ),
        ]),
        const SizedBox(height: 16),
        if (_sets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No sets yet — add the planned sets below.',
                style: TextStyle(color: _muted))))
        else
          for (final e in grouped.entries)
            Card(
              color: _card,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(e.key,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    IconButton(
                      tooltip: 'Add a set of ${e.key}',
                      icon: const Icon(Icons.add, size: 18, color: _teal),
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        final s = await promptWorkoutSet(context, initialName: e.key);
                        if (s != null) setState(() => _sets.add(s));
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  for (final set in e.value)
                    Row(children: [
                      const Text('•  ', style: TextStyle(color: _muted)),
                      Expanded(child: Text(set.detail, style: const TextStyle(fontSize: 13))),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: _muted),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _sets.remove(set)),
                      ),
                    ]),
                ]),
              ),
            ),
      ]),
    );
  }
}

// Exercise plot — driven by the shared GraphArea so it matches every other section
// (timeframes incl. All, overlay, axes, tooltips). Daily series derived from sessions.
const List<MetricDef> _exCandidates = [
  MetricDef('ex_cardio', 'Cardio load', 'exercise', MetricTier.background, ''),
  MetricDef('ex_volume', 'Volume', 'exercise', MetricTier.background, ''),
  MetricDef('ex_kcal', 'Active kcal', 'exercise', MetricTier.background, 'kcal'),
  MetricDef('ex_sessions', 'Sessions', 'exercise', MetricTier.background, ''),
  MetricDef('ex_duration', 'Duration', 'exercise', MetricTier.background, 'min'),
];

Map<String, List<Log>> _buildExerciseSeries(List<WorkoutSession> sessions) {
  final byDay = <String, List<double>>{}; // [cardio, volume, kcal, sessions, duration]
  for (final s in sessions) {
    final d = byDay.putIfAbsent(s.dateKey, () => [0, 0, 0, 0, 0]);
    d[0] += s.cardioLoad ?? 0;
    d[1] += s.volume;
    d[2] += s.summary['calories'] ?? 0;
    d[3] += 1;
    d[4] += (s.durationMins ?? 0).toDouble();
  }
  final out = {for (final m in _exCandidates) m.id: <Log>[]};
  for (final day in byDay.keys.toList()..sort()) {
    final ts = '${day}T12:00:00';
    final d = byDay[day]!;
    out['ex_cardio']!.add(Log('ex_cardio', d[0], ts: ts));
    out['ex_volume']!.add(Log('ex_volume', d[1], ts: ts));
    out['ex_kcal']!.add(Log('ex_kcal', d[2], ts: ts));
    out['ex_sessions']!.add(Log('ex_sessions', d[3], ts: ts));
    out['ex_duration']!.add(Log('ex_duration', d[4], ts: ts));
  }
  return out;
}

class _ExerciseMetricGraph extends ConsumerWidget {
  const _ExerciseMetricGraph();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = _buildExerciseSeries(ref.watch(workoutProvider));
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GraphArea(_exCandidates, logsOverride: logs),
      ),
    );
  }
}
