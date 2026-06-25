// ui/workout_screen.dart — workout logging (PDF Part 1: "lifting exercise sets" →
// volume + muscle groups; each best set updates that lift's rank). Build a session
// of sets, save it (ranks update), and see recent sessions.
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

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});
  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  final List<WorkoutSet> _building = [];

  double get _volume => _building.fold(0.0, (s, x) => s + x.volume);

  void _save() {
    if (_building.isEmpty) return;
    final bw = ref.read(currentBodyweightProvider);
    ref.read(workoutProvider.notifier).add(List.of(_building), bodyweight: bw);
    setState(_building.clear);
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
        onPressed: () => _addSetDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add set'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        _builderCard(),
        const SizedBox(height: 16),
        const Text('RECENT SESSIONS',
            style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
        const SizedBox(height: 6),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No sessions yet.', style: TextStyle(color: _muted))),
          )
        else
          for (final s in recent) _sessionRow(s),
      ]),
    );
  }

  Widget _builderCard() => Card(
        color: _card,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("THIS SESSION",
                  style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
              Text('${_volume.round()} kg·reps',
                  style: const TextStyle(color: _teal, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            if (_building.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Add sets to build your workout.', style: TextStyle(color: _muted, fontSize: 13)),
              )
            else
              for (var i = 0; i < _building.length; i++) _buildingRow(i),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _building.isEmpty ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
                child: const Text('Save workout'),
              ),
            ),
          ]),
        ),
      );

  Widget _buildingRow(int i) {
    final s = _building[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(metricById(s.exerciseId).label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text('${s.weight.round()} kg × ${s.reps}', style: const TextStyle(color: _muted)),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: _muted),
          onPressed: () => setState(() => _building.removeAt(i)),
        ),
      ]),
    );
  }

  Widget _sessionRow(WorkoutSession s) => Card(
        color: _card,
        child: ListTile(
          title: Text('${s.dateKey}  ·  ${s.sets.length} sets',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
              '${s.volume.round()} kg·reps · ${s.exercises.map((e) => metricById(e).label).join(', ')}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18, color: _muted),
            onPressed: () => ref.read(workoutProvider.notifier).remove(s.id),
          ),
        ),
      );

  Future<void> _addSetDialog(BuildContext context) async {
    final strength = metrics.where((m) => m.isStrength).toList();
    String exercise = strength.first.id;
    final weight = TextEditingController();
    final reps = TextEditingController(text: '5');
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Add set'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: exercise,
              isExpanded: true,
              dropdownColor: _card,
              decoration: const InputDecoration(labelText: 'Exercise', border: OutlineInputBorder()),
              items: [for (final m in strength) DropdownMenuItem(value: m.id, child: Text(m.label))],
              onChanged: (v) => setLocal(() => exercise = v ?? exercise),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: weight,
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
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final w = double.tryParse(weight.text);
                final r = int.tryParse(reps.text);
                if (w != null && r != null && w > 0 && r > 0) {
                  setState(() => _building.add(WorkoutSet(exercise, w, r)));
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
