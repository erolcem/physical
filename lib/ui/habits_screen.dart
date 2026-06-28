// ui/habits_screen.dart — the Habits tab. Scaffolded habits: a SECTION → a PRESET
// (or bounded custom) → cadence (daily / weekly days) + ideal time + duration.
// Verification is automatic from the day's logs (a workout, a food log, or a linked
// metric). Shows today's roster (actionable), a weekly schedule, and per-habit
// streaks. Local-first.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/habits.dart';
import '../data/habit_verify.dart';
import '../state/habit_providers.dart';
import '../state/log_providers.dart';
import '../state/providers.dart' show logsProvider;

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
    final workouts = ref.watch(workoutProvider);
    final food = ref.watch(dietProvider);
    final habits = st.habits;

    // Target-aware verification: a habit's goal is "met" when the day's data satisfies
    // its target (auto-measured habits self-complete); manual habits need a tick.
    bool met(Habit h, String day) =>
        habitGoalMet(h, day, logs: logs, food: food, workouts: workouts);
    double? measured(Habit h, String day) =>
        habitMeasured(h, day, logs: logs, food: food, workouts: workouts);
    bool done(Habit h, String day) => met(h, day) || st.completions[h.id]?.contains(day) == true;

    final dueToday = habits.where((h) => isDueToday(h)).toList();
    final doneCount = dueToday.where((h) => done(h, todayKey())).length;

    return Container(
      color: _bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _summaryCard(doneCount, dueToday.length),
          if (habits.isNotEmpty) ...[
            const SizedBox(height: 12),
            _weekRoster(habits),
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
          else ...[
            const Text('TODAY', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const SizedBox(height: 6),
            if (dueToday.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nothing scheduled today — enjoy the rest.',
                    style: TextStyle(color: _muted, fontSize: 13)),
              )
            else
              for (final h in dueToday)
                _habitTile(context, ref, h,
                    done: done(h, todayKey()),
                    streak: currentStreak(_doneDaysOf(h, st, met)),
                    status: met(h, todayKey())
                        ? HabitStatus.verified
                        : (st.doneToday(h.id) ? HabitStatus.manual : HabitStatus.notDone),
                    measuredToday: measured(h, todayKey()),
                    last7: lastNDays(7),
                    doneDays: _doneDaysOf(h, st, met)),
            // Habits scheduled on other days only (not today) — for awareness.
            for (final h in habits.where((h) => !isDueToday(h)))
              _habitTile(context, ref, h,
                  done: done(h, todayKey()), streak: currentStreak(_doneDaysOf(h, st, met)),
                  status: HabitStatus.notDone, measuredToday: null, last7: lastNDays(7),
                  doneDays: _doneDaysOf(h, st, met), dimmed: true),
          ],
        ],
      ),
    );
  }

  // Days counted "done" over the last 60: manually ticked OR the goal was met from data.
  Set<String> _doneDaysOf(Habit h, HabitsState st, bool Function(Habit, String) met) {
    final out = {...st.doneFor(h.id)};
    for (final day in lastNDays(60)) {
      if (met(h, day)) out.add(day);
    }
    return out;
  }

  // ── Today's completion ──
  Widget _summaryCard(int done, int total) {
    final frac = total == 0 ? 0.0 : done / total;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TODAY', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 6),
          Text(total == 0 ? 'Nothing due today' : '$done / $total done',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: frac, minHeight: 8,
                color: done == total && total > 0 ? _teal : _accent,
                backgroundColor: Colors.white.withValues(alpha: 0.08)),
          ),
        ]),
      ),
    );
  }

  // ── Weekly schedule (which habits land on which day) ──
  Widget _weekRoster(List<Habit> habits) {
    final todayWd = DateTime.now().weekday;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('THIS WEEK', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var wd = 1; wd <= 7; wd++)
                _dayColumn(wd, todayWd,
                    habits.where((h) => isDueOn(h, _dateForWeekday(wd))).length),
            ],
          ),
        ]),
      ),
    );
  }

  // A date this week with the given weekday (for isDueOn checks).
  DateTime _dateForWeekday(int wd) {
    final now = DateTime.now();
    return now.add(Duration(days: wd - now.weekday));
  }

  Widget _dayColumn(int wd, int today, int count) {
    final isToday = wd == today;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 30,
        height: 30 + (count > 0 ? (count.clamp(1, 4)) * 6 : 0).toDouble(),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: count > 0
              ? (isToday ? _accent : _accent.withValues(alpha: 0.3))
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(count > 0 ? '$count' : '',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      ),
      const SizedBox(height: 4),
      Text(weekdayShort[wd - 1][0],
          style: TextStyle(
              fontSize: 10,
              color: isToday ? _accent : _muted,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600)),
    ]);
  }

  Widget _empty() => const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Column(children: [
          Icon(Icons.checklist_rtl, size: 48, color: _muted),
          SizedBox(height: 12),
          Text('Build your accountability layer', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Tap “Add habit” to commit to a daily or weekly action.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 13)),
        ]),
      );

  // ── One habit row ──
  Widget _habitTile(BuildContext context, WidgetRef ref, Habit h,
      {required bool done,
      required int streak,
      required HabitStatus status,
      required double? measuredToday,
      required List<String> last7,
      required Set<String> doneDays,
      bool dimmed = false}) {
    final sec = sectionOf(h.section);
    final cc = Color(sec.color);
    return Opacity(
      opacity: dimmed ? 0.5 : 1.0,
      child: Dismissible(
        key: ValueKey(h.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) => ref.read(habitsProvider.notifier).removeHabit(h.id),
        child: Card(
          color: _card,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: dimmed ? null : () => ref.read(habitsProvider.notifier).toggleToday(h.id),
            child: IntrinsicHeight(
              child: Row(children: [
                Container(width: 4, color: cc),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(children: [
                      Icon(done ? Icons.check_circle : Icons.circle_outlined,
                          color: done ? _teal : _muted, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text('${sec.emoji} ', style: const TextStyle(fontSize: 13)),
                            Flexible(
                              child: Text(h.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15,
                                      decoration: done ? TextDecoration.lineThrough : null,
                                      color: done ? _muted : Colors.white)),
                            ),
                          ]),
                          if (h.target != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: _progress(h, measuredToday, status == HabitStatus.verified),
                            ),
                          if (_pills(h).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(spacing: 6, runSpacing: 4, children: _pills(h)),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              for (final day in last7) _weekDot(doneDays.contains(day)),
                            ]),
                          ),
                        ]),
                      ),
                      if (status == HabitStatus.verified)
                        _badge('✓ verified', _teal)
                      else if (streak > 0)
                        _badge('🔥 $streak', _accent),
                      if (h.time != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 18, color: _muted,
                          tooltip: 'Add to calendar',
                          icon: const Icon(Icons.event),
                          onPressed: () => _addToCalendar(h),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // Target progress: a thin bar + "measured / target unit", teal when the goal is met.
  Widget _progress(Habit h, double? measured, bool met) {
    final tgt = h.target!;
    final m = measured ?? 0;
    final frac = (h.compare == 'lte'
            ? (measured == null ? 0.0 : (m <= tgt ? 1.0 : (tgt <= 0 ? 0.0 : tgt / m)))
            : (tgt <= 0 ? 0.0 : m / tgt))
        .clamp(0.0, 1.0);
    final c = met ? _teal : _accent;
    String n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    final unit = h.unit.isEmpty || h.unit.startsWith('/') ? '' : ' ${h.unit}';
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              value: frac, minHeight: 4, color: c,
              backgroundColor: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      const SizedBox(width: 8),
      Text('${measured == null ? '–' : n(m)} ${h.compare == 'lte' ? '≤' : '/'} ${n(tgt)}$unit',
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
    ]);
  }

  List<Widget> _pills(Habit h) => [
        if (h.time != null) _pill('⏰ ${_fmt12(h.time!)}', _muted),
        if (h.durationMins > 0) _pill('⏱ ${_fmtDur(h.durationMins)}', _muted),
        if (h.cadence == 'weekly' && h.days.isNotEmpty)
          _pill('📅 ${h.days.map((d) => weekdayShort[d - 1]).join(' ')}', _muted),
        if (h.verify != 'manual') _pill('auto-verify', _teal),
      ];

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: c)),
      );

  Widget _weekDot(bool done) => Container(
        width: 9, height: 9,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? _teal : Colors.transparent,
          border: done ? null : Border.all(color: _muted.withValues(alpha: 0.5)),
        ),
      );

  Widget _badge(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
      );

  Future<void> _addToCalendar(Habit h) async {
    final url = googleCalendarUrl(h);
    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ── Add habit: section → preset (or custom) → cadence/time/duration ──
  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    String section = 'sleep';
    HabitPreset? preset;
    final titleCtrl = TextEditingController();
    final durCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final productsCtrl = TextEditingController();
    String compare = 'gte';
    String? goalKey;
    String unit = '';
    String? time;
    String cadence = 'daily';
    final days = <int>{};

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final presets = presetsFor(section);
          return AlertDialog(
            backgroundColor: _card,
            title: const Text('New habit'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Section', style: TextStyle(fontSize: 11, color: _muted)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  for (final s in habitSections.values)
                    ChoiceChip(
                      label: Text('${s.emoji} ${s.label}'),
                      selected: section == s.id,
                      selectedColor: Color(s.color).withValues(alpha: 0.25),
                      onSelected: (_) => setLocal(() {
                        section = s.id;
                        preset = null;
                        titleCtrl.clear();
                        targetCtrl.clear();
                        goalKey = null; unit = ''; compare = 'gte';
                      }),
                    ),
                ]),
                const SizedBox(height: 12),
                const Text('Choose one', style: TextStyle(fontSize: 11, color: _muted)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final p in presets)
                    ChoiceChip(
                      label: Text(p.title),
                      selected: preset?.title == p.title,
                      selectedColor: _accent.withValues(alpha: 0.25),
                      onSelected: (_) => setLocal(() {
                        preset = p;
                        titleCtrl.text = p.title;
                        targetCtrl.text = p.target == null
                            ? ''
                            : (p.target == p.target!.roundToDouble()
                                ? p.target!.round().toString()
                                : p.target.toString());
                        compare = p.compare;
                        goalKey = p.goalKey;
                        unit = p.unit;
                      }),
                    ),
                  ChoiceChip(
                    label: const Text('✏️ Custom'),
                    selected: preset == null && titleCtrl.text.isNotEmpty,
                    onSelected: (_) => setLocal(() {
                      preset = null;
                      titleCtrl.clear();
                      targetCtrl.clear();
                      goalKey = null; unit = ''; compare = 'gte';
                    }),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Habit', border: OutlineInputBorder()),
                ),
                // Quantitative target (Table 2) — only for auto-measured sections.
                if (section != 'aesthetics' && section != 'misc') ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    ToggleButtons(
                      isSelected: [compare == 'gte', compare == 'lte'],
                      onPressed: (i) => setLocal(() => compare = i == 0 ? 'gte' : 'lte'),
                      borderRadius: BorderRadius.circular(8),
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      children: const [Text('≥'), Text('≤')],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Target${unit.isEmpty ? ' (optional)' : ' ($unit)'}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ]),
                ],
                // Aesthetics: record the products/items used in this routine (for the AI).
                if (section == 'aesthetics') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: productsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Products used (comma-separated)',
                      hintText: 'e.g. CeraVe cleanser, 2% BHA, SPF50',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  ChoiceChip(
                      label: const Text('Daily'),
                      selected: cadence == 'daily',
                      onSelected: (_) => setLocal(() => cadence = 'daily')),
                  const SizedBox(width: 8),
                  ChoiceChip(
                      label: const Text('Weekly'),
                      selected: cadence == 'weekly',
                      onSelected: (_) => setLocal(() => cadence = 'weekly')),
                ]),
                if (cadence == 'weekly') ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 4, children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(weekdayShort[d - 1]),
                        selected: days.contains(d),
                        onSelected: (on) => setLocal(() => on ? days.add(d) : days.remove(d)),
                      ),
                  ]),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(time == null ? 'Ideal time' : _fmt12(time!)),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: const TimeOfDay(hour: 7, minute: 0));
                        if (t != null) {
                          setLocal(() => time =
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
                      decoration: const InputDecoration(labelText: 'Mins', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final verify = preset?.verify ??
                      (section == 'exercise' ? 'workout' : section == 'diet' ? 'diet' : 'manual');
                  final products = section == 'aesthetics'
                      ? [for (final p in productsCtrl.text.split(',')) if (p.trim().isNotEmpty) p.trim()]
                      : const <String>[];
                  ref.read(habitsProvider.notifier).addHabit(
                        titleCtrl.text,
                        section: section,
                        verify: verify,
                        linkedMetricId: preset?.linkedMetricId,
                        target: double.tryParse(targetCtrl.text.trim()),
                        compare: compare,
                        goalKey: goalKey,
                        unit: unit,
                        products: products,
                        time: time,
                        durationMins: int.tryParse(durCtrl.text) ?? 0,
                        cadence: cadence,
                        days: cadence == 'weekly' ? days.toList() : const [],
                      );
                  Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

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
