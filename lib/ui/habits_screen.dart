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
import '../data/sync.dart' show apiClientProvider;
import '../state/habit_providers.dart';
import '../state/log_providers.dart';
import '../state/providers.dart' show logsProvider;

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
const _teal = Color(0xFF4CE0C3);
const _muted = Color(0xFF7880A8);

class HabitsTab extends ConsumerStatefulWidget {
  const HabitsTab({super.key});
  @override
  ConsumerState<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends ConsumerState<HabitsTab> {
  bool _week = false; // Day (false) / Week (true)

  @override
  Widget build(BuildContext context) {
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

    // Time-ordered: timed habits first (by clock), then untimed.
    int byTime(Habit a, Habit b) {
      final ta = a.time, tb = b.time;
      if (ta == null && tb == null) return a.title.compareTo(b.title);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    }

    final dueToday = habits.where((h) => isDueToday(h)).toList()..sort(byTime);
    final doneCount = dueToday.where((h) => done(h, todayKey())).length;

    return Container(
      color: _bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // Day / Week toggle.
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Day'), icon: Icon(Icons.today, size: 16)),
                ButtonSegment(value: true, label: Text('Week'), icon: Icon(Icons.calendar_view_week, size: 16)),
              ],
              selected: {_week},
              onSelectionChanged: (s) => setState(() => _week = s.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton.icon(
              onPressed: () => _subscribeCalendar(context, ref),
              icon: const Icon(Icons.event_available, size: 18),
              label: const Text('Subscribe'),
              style: TextButton.styleFrom(foregroundColor: _muted),
            ),
            TextButton.icon(
              onPressed: () => _showAddDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add habit'),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ]),
          if (habits.isEmpty)
            _empty()
          else if (_week) ...[
            _budgetCard(habits),
            const SizedBox(height: 12),
            _weekView(habits, st, met, done),
          ]
          else ...[
            _summaryCard(doneCount, dueToday.length,
                verified: dueToday.where((h) => met(h, todayKey())).length,
                missed: [for (final h in dueToday) if (!done(h, todayKey())) h]),
            const SizedBox(height: 12),
            _budgetCard(habits),
            const SizedBox(height: 12),
            if (dueToday.isNotEmpty) _densityBar(dueToday),
            const SizedBox(height: 12),
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
            for (final h in (habits.where((h) => !isDueToday(h)).toList()..sort(byTime)))
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

  // ── Today's accountability recap: done / total · verified, + what's still missed ──
  Widget _summaryCard(int done, int total, {required int verified, required List<Habit> missed}) {
    final frac = total == 0 ? 0.0 : done / total;
    final allDone = done == total && total > 0;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('TODAY', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const Spacer(),
            if (verified > 0)
              Text('$verified auto-verified', style: const TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Text(total == 0 ? 'Nothing due today' : (allDone ? 'All $total done 🎉' : '$done / $total done'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: frac, minHeight: 8,
                color: allDone ? _teal : _accent,
                backgroundColor: Colors.white.withValues(alpha: 0.08)),
          ),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Still to do', style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: _muted.withValues(alpha: 0.8))),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final h in missed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(sectionOf(h.section).color).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${sectionOf(h.section).emoji} ${h.title}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  // ── Planner/budgeter rollup: scheduled time + money per month + habit count ──
  Widget _budgetCard(List<Habit> habits) {
    final b = monthlyBudget(habits);
    Widget stat(String v, String l, Color c) => Expanded(
          child: Column(children: [
            Text(v, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: c)),
            const SizedBox(height: 2),
            Text(l, style: const TextStyle(fontSize: 9.5, letterSpacing: 1, color: _muted, fontWeight: FontWeight.w700)),
          ]),
        );
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          stat('${b.hoursPerMonth.toStringAsFixed(b.hoursPerMonth < 10 ? 1 : 0)} h', 'TIME / MONTH', _accent),
          stat('£${b.costPerMonth.toStringAsFixed(b.costPerMonth < 100 ? 0 : 0)}', 'COST / MONTH', _teal),
          stat('${habits.length}', 'HABITS', Colors.white),
        ]),
      ),
    );
  }

  // ── 24h density bar: how the day's habits are distributed across the clock ──
  Widget _densityBar(List<Habit> due) {
    final d = hourDensity(due);
    final maxC = [...d, 1].reduce((a, b) => a > b ? a : b);
    final untimed = due.where((h) => h.time == null).length;
    final nowHour = DateTime.now().hour;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('THROUGH THE DAY', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const Spacer(),
            if (untimed > 0) Text('$untimed anytime', style: const TextStyle(fontSize: 10.5, color: _muted)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var h = 0; h < 24; h++)
                Expanded(
                  child: Container(
                    height: d[h] == 0 ? 3 : 6 + 32 * (d[h] / maxC),
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: d[h] > 0
                          ? (h == nowHour ? _teal : _accent)
                          : (h == nowHour ? _teal.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('12a', style: TextStyle(fontSize: 9, color: _muted)),
            Text('6a', style: TextStyle(fontSize: 9, color: _muted)),
            Text('12p', style: TextStyle(fontSize: 9, color: _muted)),
            Text('6p', style: TextStyle(fontSize: 9, color: _muted)),
            Text('12a', style: TextStyle(fontSize: 9, color: _muted)),
          ]),
        ]),
      ),
    );
  }

  // ── Week view: a 7-day calendar grid with each day's habits as section-coloured chips ──
  Widget _weekView(List<Habit> habits, HabitsState st,
      bool Function(Habit, String) met, bool Function(Habit, String) done) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('THIS WEEK', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 10),
          for (var i = 0; i < 7; i++) ...[
            () {
              final date = DateTime(monday.year, monday.month, monday.day + i);
              final key = dateKey(date);
              final isToday = key == todayKey();
              final dayHabits = habits.where((h) => isDueOn(h, date)).toList();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 34,
                    child: Column(children: [
                      Text(weekdayShort[i].substring(0, 1),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                              color: isToday ? _accent : Colors.white)),
                      Text('${date.day}', style: TextStyle(fontSize: 10, color: isToday ? _accent : _muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: dayHabits.isEmpty
                        ? Text('—', style: TextStyle(color: _muted.withValues(alpha: 0.5)))
                        : Wrap(spacing: 5, runSpacing: 5, children: [
                            for (final h in dayHabits)
                              () {
                                final d = done(h, key);
                                final c = Color(sectionOf(h.section).color);
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: d ? c.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: d ? c : Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  child: Text(
                                      '${sectionOf(h.section).emoji} ${h.title}${d ? ' ✓' : ''}',
                                      style: TextStyle(fontSize: 10.5,
                                          color: d ? Colors.white : Colors.white60)),
                                );
                              }(),
                          ]),
                  ),
                ]),
              );
            }(),
            if (i < 6) Divider(color: Colors.white.withValues(alpha: 0.05), height: 12),
          ],
        ]),
      ),
    );
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
        if (h.cost > 0) _pill('£${h.cost == h.cost.roundToDouble() ? h.cost.round() : h.cost}', _muted),
        if (h.cadence == 'weekly' && h.days.isNotEmpty)
          _pill('📅 ${h.days.map((d) => weekdayShort[d - 1]).join(' ')}', _muted),
        if (h.verify != 'manual') _pill('auto-verify', _teal),
        for (final p in h.products) _pill('🧴 $p', const Color(0xFFE67BE6)),
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

  // One-time subscription: opens the user's personal habit ICS feed in their calendar
  // app (webcal://). All habits + future edits then appear + auto-refresh — no per-habit
  // taps. Needs the user signed in + synced (the feed reads their backup).
  Future<void> _subscribeCalendar(BuildContext context, WidgetRef ref) async {
    final url = await ref.read(apiClientProvider).calendarFeedUrl();
    if (!context.mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sign in and ☁ sync first to get your habit calendar feed.')));
      return;
    }
    // webcal:// makes the calendar app offer to subscribe (auto-refreshing).
    final webcal = url.replaceFirst(RegExp(r'^https?://'), 'webcal://');
    await launchUrl(Uri.parse(webcal), mode: LaunchMode.externalApplication);
  }

  // ── Add habit: section → preset (or custom) → cadence/time/duration ──
  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    String section = 'sleep';
    HabitPreset? preset;
    final titleCtrl = TextEditingController();
    final durCtrl = TextEditingController();
    final costCtrl = TextEditingController();
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cost', prefixText: '£', border: OutlineInputBorder()),
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
                        cost: double.tryParse(costCtrl.text.trim()) ?? 0,
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
