// ui/workout_screen.dart — workout tracker (PDF Part 1). Build a session like a
// real tracker: add an EXERCISE, then add its SETS (weight × reps); repeat. On
// save we record the session (volume + muscle groups) and update each exercise's
// rank from its best set. Recent sessions are shown grouped by exercise.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metrics.dart';
import '../data/workout.dart';
import '../state/log_providers.dart';
import '../state/providers.dart' show currentBodyweightProvider;

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _teal = Color(0xFF4CE0C3);
const _accent = Color(0xFF5B6AF8);
const _muted = Color(0xFF7880A8);

void openWorkoutScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkoutScreen()));
}

/// One exercise being built, with its ordered sets.
class _BuildExercise {
  final String exerciseId;
  final List<WorkoutSet> sets = [];
  _BuildExercise(this.exerciseId);
  double get volume => sets.fold(0.0, (s, x) => s + x.volume);
}

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});
  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  final List<_BuildExercise> _exercises = [];

  double get _volume => _exercises.fold(0.0, (s, e) => s + e.volume);
  int get _setCount => _exercises.fold(0, (s, e) => s + e.sets.length);

  void _save() {
    final sets = [for (final e in _exercises) ...e.sets];
    if (sets.isEmpty) return;
    final bw = ref.read(currentBodyweightProvider);
    ref.read(workoutProvider.notifier).add(sets, bodyweight: bw);
    setState(_exercises.clear);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Workout saved — ranks updated'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(workoutProvider);
    final recent = sessions.reversed.take(8).toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Workout')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        onPressed: _addExerciseDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        _builderCard(),
        const SizedBox(height: 16),
        if (sessions.isNotEmpty) ...[
          _trainingStats(sessions),
          const SizedBox(height: 16),
        ],
        const Text('RECENT SESSIONS', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
        const SizedBox(height: 6),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No sessions yet.', style: TextStyle(color: _muted))))
        else
          for (final s in recent) _sessionRow(s),
      ]),
    );
  }

  // Per-domain training layout: a 7-day volume trend + this week's totals.
  Widget _trainingStats(List<WorkoutSession> sessions) {
    final perDay = volumePerDay(sessions, days: 7);
    final maxV = perDay.fold<double>(1, (m, v) => v > m ? v : m);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LAST 7 DAYS · TRAINING', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < perDay.length; i++)
                Container(
                  width: 22,
                  height: 4 + 40 * (perDay[i] / maxV),
                  decoration: BoxDecoration(
                      color: i == perDay.length - 1 ? _teal : _teal.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat('${volumeOverDays(sessions, days: 7).round()}', 'volume'),
            _stat('${sessionsOverDays(sessions, days: 7)}', 'sessions'),
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

  Widget _builderCard() => Card(
        color: _card,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('THIS SESSION', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
              Text('$_setCount sets · ${_volume.round()} vol',
                  style: const TextStyle(color: _teal, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            if (_exercises.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Tap "Add exercise", then log its sets.',
                    style: TextStyle(color: _muted, fontSize: 13)))
            else
              for (var i = 0; i < _exercises.length; i++) _exerciseBlock(i),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _setCount == 0 ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
                child: const Text('Save workout'),
              ),
            ),
          ]),
        ),
      );

  Widget _exerciseBlock(int i) {
    final e = _exercises[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFF0E1124), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(metricById(e.exerciseId).label,
              style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(
            visualDensity: VisualDensity.compact, iconSize: 16, color: _muted,
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _exercises.removeAt(i)),
          ),
        ]),
        for (var j = 0; j < e.sets.length; j++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 28, child: Text('${j + 1}',
                  style: const TextStyle(color: _muted, fontSize: 12))),
              Text('${e.sets[j].weight.round()} kg × ${e.sets[j].reps}',
                  style: const TextStyle(fontSize: 13)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => e.sets.removeAt(j)),
                child: const Icon(Icons.close, size: 14, color: _muted),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addSetDialog(e),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Set'),
            style: TextButton.styleFrom(foregroundColor: _accent, padding: EdgeInsets.zero),
          ),
        ),
      ]),
    );
  }

  Widget _sessionRow(WorkoutSession s) {
    final groups = groupByExercise(s.sets);
    final summary = groups.entries
        .map((g) => '${metricById(g.key).label} ${g.value.length}×')
        .join(' · ');
    return Card(
      color: _card,
      child: ListTile(
        title: Text('${s.dateKey}  ·  ${s.sets.length} sets · ${s.volume.round()} vol',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(summary, style: const TextStyle(fontSize: 12, color: _muted)),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18, color: _muted),
          onPressed: () => ref.read(workoutProvider.notifier).remove(s.id),
        ),
      ),
    );
  }

  Future<void> _addExerciseDialog() async {
    final strength = metrics.where((m) => m.isStrength).toList();
    String exercise = strength.first.id;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Add exercise'),
          content: DropdownButtonFormField<String>(
            initialValue: exercise,
            isExpanded: true,
            dropdownColor: _card,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [for (final m in strength) DropdownMenuItem(value: m.id, child: Text(m.label))],
            onChanged: (v) => setLocal(() => exercise = v ?? exercise),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                setState(() => _exercises.add(_BuildExercise(exercise)));
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSetDialog(_BuildExercise e) async {
    final weight = TextEditingController(
        text: e.sets.isNotEmpty ? e.sets.last.weight.round().toString() : '');
    final reps = TextEditingController(
        text: e.sets.isNotEmpty ? e.sets.last.reps.toString() : '5');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Set · ${metricById(e.exerciseId).label}'),
        content: Row(children: [
          Expanded(
            child: TextField(
              controller: weight, autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: reps,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reps', border: OutlineInputBorder()),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final w = double.tryParse(weight.text);
              final r = int.tryParse(reps.text);
              if (w != null && r != null && w > 0 && r > 0) {
                setState(() => e.sets.add(WorkoutSet(e.exerciseId, w, r)));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add set'),
          ),
        ],
      ),
    );
  }
}
