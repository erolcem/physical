// ui/habits_screen.dart — the Habits accountability tab. Today's completion
// summary, per-habit check-off with streaks, and two-step verification badges
// (a tick corroborated by a same-day log of the linked metric). Add/remove are
// in-tab; storage is local-first via the Habits notifier.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/habits.dart';
import '../data/metrics.dart';
import '../state/habit_providers.dart';
import '../state/providers.dart';

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
const _teal = Color(0xFF4CE0C3);
const _muted = Color(0xFF7880A8);

class HabitsTab extends ConsumerWidget {
  const HabitsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(habitsProvider);
    final logs = ref.watch(logsProvider);
    final habits = st.habits;

    final doneCount = habits.where((h) => st.doneToday(h.id)).length;

    bool linkedLogToday(Habit h) =>
        h.linkedMetricId != null &&
        (logs[h.linkedMetricId]?.any((l) => l.ts.startsWith(todayKey())) ?? false);

    return Container(
      color: _bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _summaryCard(doneCount, habits.length),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showAddDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add habit'),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ),
          if (habits.isEmpty)
            _empty()
          else
            for (final h in habits)
              _habitTile(context, ref, h,
                  done: st.doneToday(h.id),
                  streak: currentStreak(st.doneFor(h.id)),
                  status: statusFor(h,
                      doneToday: st.doneToday(h.id),
                      hasLinkedLogToday: linkedLogToday(h))),
        ],
      ),
    );
  }

  Widget _summaryCard(int done, int total) {
    final frac = total == 0 ? 0.0 : done / total;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TODAY',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 6),
          Text(total == 0 ? 'No habits yet' : '$done / $total done',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                color: done == total && total > 0 ? _teal : _accent,
                backgroundColor: Colors.white.withValues(alpha: 0.08)),
          ),
        ]),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(children: const [
          Icon(Icons.checklist_rtl, size: 48, color: _muted),
          SizedBox(height: 12),
          Text('Build your accountability layer',
              style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Tap “Add habit” to commit to a daily action.',
              style: TextStyle(color: _muted, fontSize: 13)),
        ]),
      );

  Widget _habitTile(BuildContext context, WidgetRef ref, Habit h,
      {required bool done, required int streak, required HabitStatus status}) {
    return Dismissible(
      key: ValueKey(h.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(habitsProvider.notifier).removeHabit(h.id),
      child: Card(
        color: _card,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => ref.read(habitsProvider.notifier).toggleToday(h.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(done ? Icons.check_circle : Icons.circle_outlined,
                  color: done ? _teal : _muted, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: done ? _muted : Colors.white)),
                      if (h.linkedMetricId != null)
                        Text('verifies with ${metricById(h.linkedMetricId!).label}',
                            style: const TextStyle(fontSize: 11, color: _muted)),
                    ]),
              ),
              if (status == HabitStatus.verified)
                _badge('✓ verified', _teal)
              else if (streak > 0)
                _badge('🔥 $streak', _accent),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                color: c, fontWeight: FontWeight.w800, fontSize: 12)),
      );

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    String? linked; // metric id to verify against, or null
    // Metrics worth corroborating against: ranked + auto-synced.
    final linkable = metrics
        .where((m) => m.tier == MetricTier.ranked || m.autoSync)
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: _card,
          title: const Text('New habit'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'e.g. Train, 8h sleep, hit protein',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: linked,
              isExpanded: true,
              dropdownColor: _card,
              decoration: const InputDecoration(
                  labelText: 'Verify with (optional)',
                  border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Manual only')),
                for (final m in linkable)
                  DropdownMenuItem<String?>(value: m.id, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => linked = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                ref
                    .read(habitsProvider.notifier)
                    .addHabit(ctrl.text, linkedMetricId: linked);
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
