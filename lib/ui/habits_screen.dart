// ui/habits_screen.dart — the Habits tab. Reconciles the planner/budgeter
// (category, time, duration, monthly time/$ rollup, a 24h density bar) with the
// accountability layer (today's summary, per-habit check-off, streaks, and
// two-step verification badges). Add/remove in-tab; storage is local-first.
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
const _gold = Color(0xFFF6CF3E);
const _muted = Color(0xFF7880A8);

class HabitsTab extends ConsumerWidget {
  const HabitsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(habitsProvider);
    final logs = ref.watch(logsProvider);
    final habits = st.habits;
    final doneCount = habits.where((h) => st.doneToday(h.id)).length;

    bool verifiedOn(Habit h, String day) =>
        h.linkedMetricId != null &&
        (logs[h.linkedMetricId]?.any((l) => l.ts.startsWith(day)) ?? false);
    final last7 = lastNDays(7);

    return Container(
      color: _bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _summaryCard(doneCount, habits.length),
          if (habits.isNotEmpty) ...[
            const SizedBox(height: 12),
            _planCard(habits),
            const SizedBox(height: 12),
            _weekCard(habits, st.completions),
          ],
          const SizedBox(height: 4),
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
                      hasLinkedLogToday: verifiedOn(h, todayKey())),
                  last7: last7,
                  doneDays: st.doneFor(h.id),
                  verifiedOn: (day) => verifiedOn(h, day)),
        ],
      ),
    );
  }

  // ── Today's accountability summary ──
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

  // ── Planner / budgeter rollup + 24h density bar ──
  Widget _planCard(List<Habit> habits) {
    final plan = planFor(habits);
    final slots = densitySlots(habits);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('YOUR DAY',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _stat(_fmtDur(plan.minutesPerDay), 'per day', _teal),
            _stat(_fmtDur(plan.minutesPerMonth), 'per month', _accent),
            _stat(plan.costPerMonth > 0 ? '\$${plan.costPerMonth.toStringAsFixed(0)}' : '—',
                'cost/mo', _gold),
            _stat('${plan.pctOfMonth.toStringAsFixed(1)}%', 'of month',
                const Color(0xFFE67BE6)),
          ]),
          const SizedBox(height: 14),
          _densityBar(slots),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label, Color c) => Column(children: [
        Text(value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: c)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
      ]);

  Widget _densityBar(List<DaySlot> slots) {
    final hasAny = slots.any((s) => s.categoryId != null);
    if (!hasAny) {
      return const Text('Add a time + duration to a habit to map your day',
          style: TextStyle(fontSize: 11, color: _muted));
    }
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            for (final s in slots)
              Expanded(
                child: Container(
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 0.3),
                  color: s.categoryId == null
                      ? Colors.white.withValues(alpha: 0.05)
                      : Color(categoryOf(s.categoryId!).color)
                          .withValues(alpha: (0.35 + s.overlap * 0.2).clamp(0.0, 0.9)),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
        Text('12am', style: TextStyle(fontSize: 8, color: _muted)),
        Text('6am', style: TextStyle(fontSize: 8, color: _muted)),
        Text('12pm', style: TextStyle(fontSize: 8, color: _muted)),
        Text('6pm', style: TextStyle(fontSize: 8, color: _muted)),
        Text('12am', style: TextStyle(fontSize: 8, color: _muted)),
      ]),
    ]);
  }

  // ── Weekly history (the Phase 2 exit-gate summary) ──
  Widget _weekCard(List<Habit> habits, Map<String, Set<String>> completions) {
    final counts = dailyDoneCounts(habits, completions);
    final days = lastNDays(7);
    final total = habits.length;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LAST 7 DAYS',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${counts[i]}',
                      style: const TextStyle(fontSize: 10, color: _muted)),
                  const SizedBox(height: 3),
                  Container(
                    width: 22,
                    height: total == 0 ? 3 : 3 + 30 * counts[i] / total,
                    decoration: BoxDecoration(
                        color: counts[i] == total && total > 0 ? _teal : _accent,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 4),
                  Text(_weekdayLetter(days[i]),
                      style: const TextStyle(fontSize: 9, color: _muted)),
                ]),
            ],
          ),
        ]),
      ),
    );
  }

  String _weekdayLetter(String dayKey) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return letters[DateTime.parse(dayKey).weekday - 1];
  }

  Widget _weekDot(bool done, bool verified) => Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? (verified ? _teal : _accent) : Colors.transparent,
          border:
              done ? null : Border.all(color: _muted.withValues(alpha: 0.5)),
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 40),
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

  // ── One habit row ──
  Widget _habitTile(BuildContext context, WidgetRef ref, Habit h,
      {required bool done,
      required int streak,
      required HabitStatus status,
      required List<String> last7,
      required Set<String> doneDays,
      required bool Function(String day) verifiedOn}) {
    final cat = categoryOf(h.category);
    final cc = Color(cat.color);
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
          child: IntrinsicHeight(
            child: Row(children: [
              Container(width: 4, color: cc), // category accent bar
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(children: [
                    Icon(done ? Icons.check_circle : Icons.circle_outlined,
                        color: done ? _teal : _muted, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text('${cat.emoji} ',
                                  style: const TextStyle(fontSize: 13)),
                              Flexible(
                                child: Text(h.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        decoration: done
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: done ? _muted : Colors.white)),
                              ),
                            ]),
                            if (_pills(h).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(spacing: 6, runSpacing: 4, children: _pills(h)),
                              ),
                            if (h.linkedMetricId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                    'verifies with ${metricById(h.linkedMetricId!).label}',
                                    style: const TextStyle(fontSize: 10, color: _muted)),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(children: [
                                for (final day in last7)
                                  _weekDot(doneDays.contains(day),
                                      doneDays.contains(day) && verifiedOn(day)),
                              ]),
                            ),
                          ]),
                    ),
                    if (status == HabitStatus.verified)
                      _badge('✓ verified', _teal)
                    else if (streak > 0)
                      _badge('🔥 $streak', _accent),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _pills(Habit h) => [
        if (h.time != null) _pill('⏰ ${_fmt12(h.time!)}', _muted),
        if (h.durationMins > 0) _pill('⏱ ${_fmtDur(h.durationMins)}', _muted),
        if (h.costPerMonth > 0) _pill('💰 \$${h.costPerMonth.toStringAsFixed(0)}/mo', _gold),
      ];

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: c)),
      );

  Widget _badge(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
      );

  // ── Add habit ──
  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final durCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    String cat = 'fitness';
    String? time; // 'HH:MM'
    String? linked;
    final linkable = metrics
        .where((m) => m.tier == MetricTier.ranked || m.autoSync)
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: _card,
          title: const Text('New habit'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'e.g. Train, 8h sleep, hit protein',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final c in habitCategories.values)
                    ChoiceChip(
                      label: Text('${c.emoji} ${c.label}'),
                      selected: cat == c.id,
                      onSelected: (_) => setState(() => cat = c.id),
                      selectedColor: Color(c.color).withValues(alpha: 0.25),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(time == null ? 'Time' : _fmt12(time!)),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: ctx, initialTime: const TimeOfDay(hour: 7, minute: 0));
                      if (t != null) {
                        setState(() => time =
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: durCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Mins', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '\$/mo', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
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
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                ref.read(habitsProvider.notifier).addHabit(
                      nameCtrl.text,
                      category: cat,
                      time: time,
                      durationMins: int.tryParse(durCtrl.text) ?? 0,
                      costPerMonth: double.tryParse(costCtrl.text) ?? 0,
                      linkedMetricId: linked,
                    );
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ── format helpers ──
  String _fmt12(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  String _fmtDur(int mins) {
    if (mins <= 0) return '—';
    final h = mins ~/ 60, m = mins % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
