// ui/habits_screen.dart — the Habits tab. Scaffolded habits: a SECTION → a PRESET
// (or bounded custom) → cadence (daily / weekly days) + ideal time + duration.
// Verification is automatic from the day's logs (a workout, a food log, or a linked
// metric). Shows today's roster (actionable), a weekly schedule, and per-habit
// streaks. Local-first.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/ai_verify.dart' show runAiVerification;
import '../data/api_client.dart' show ApiException;
import '../data/habits.dart';
import '../data/habit_verify.dart';
import '../data/repository.dart' show Repository;
import '../data/sync.dart' show apiClientProvider;
import '../state/habit_providers.dart';
import '../state/log_providers.dart';
import '../state/providers.dart' show logsProvider, repositoryProvider;
import 'exercise_screen.dart' show SessionDetailScreen, TemplateEditorScreen;

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
  bool _calBusy = false; // calendar push in flight
  bool _aiBusy = false; // AI verification in flight
  DateTime _selected = DateTime.now(); // the day being viewed (item: browse any day)

  bool get _viewingToday => dateKey(_selected) == todayKey();

  String _dayLabel(DateTime d) {
    final key = dateKey(d);
    if (key == todayKey()) return 'Today';
    if (key == dateKey(DateTime.now().subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdayShort[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(habitsProvider);
    final logs = ref.watch(logsProvider);
    final workouts = ref.watch(workoutProvider);
    final food = ref.watch(dietProvider);
    final habits = st.habits;
    final dayKey0 = dateKey(_selected);

    // Target-aware verification: a habit's goal is "met" when the day's data satisfies
    // its target (auto-measured habits self-complete); manual habits need a tick.
    bool met(Habit h, String day) =>
        habitGoalMet(h, day, logs: logs, food: food, workouts: workouts);
    double? measured(Habit h, String day) =>
        habitMeasured(h, day, logs: logs, food: food, workouts: workouts);
    // Forgiving model: a tick always counts; evidence (AI verdict first, else the
    // rule-based check) can ALSO complete auto-verifiable habits on its own — and
    // earns the "verified" badge a bare tick doesn't get.
    bool done(Habit h, String day) => habitDoneOn(h, day,
        logs: logs, food: food, workouts: workouts, ticked: st.completions[h.id],
        aiVerdict: st.aiVerdictFor(h.id, day));
    // Verified = evidence-backed (AI verdict when it has run, else rules).
    bool verified(Habit h, String day) =>
        h.verify != 'manual' &&
        (st.aiVerdictFor(h.id, day) ?? met(h, day)) == true;

    // Time-ordered: timed habits first (by clock), then untimed.
    int byTime(Habit a, Habit b) {
      final ta = a.time, tb = b.time;
      if (ta == null && tb == null) return a.title.compareTo(b.title);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    }

    final dueToday = habits.where((h) => isDueOn(h, _selected)).toList()..sort(byTime);
    final doneCount = dueToday.where((h) => done(h, dayKey0)).length;

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
          if (!_week) ...[
            const SizedBox(height: 6),
            // Browse any day — arrows step a day at a time; tap the label to jump
            // back to today. Forward stops at today (the week view covers ahead).
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left, color: _muted),
                onPressed: () => setState(
                    () => _selected = _selected.subtract(const Duration(days: 1))),
              ),
              TextButton(
                onPressed: _viewingToday
                    ? null
                    : () => setState(() => _selected = DateTime.now()),
                child: Text(_dayLabel(_selected),
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: _viewingToday ? Colors.white : _teal)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.chevron_right,
                    color: _viewingToday ? _muted.withValues(alpha: 0.3) : _muted),
                onPressed: _viewingToday
                    ? null
                    : () => setState(
                        () => _selected = _selected.add(const Duration(days: 1))),
              ),
            ]),
          ] else
            const SizedBox(height: 12),
          // Wrap (not Row) so the actions never overflow on narrow screens.
          Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
            TextButton.icon(
              onPressed: _calBusy ? null : () => _pushCalendar(context, ref),
              icon: _calBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.event_available, size: 18),
              label: const Text('Calendar'),
              style: TextButton.styleFrom(
                  foregroundColor: _muted, visualDensity: VisualDensity.compact),
            ),
            // On-demand LLM verification of the shown day (also runs on every sync).
            TextButton.icon(
              onPressed: _aiBusy ? null : () => _aiVerify(context, ref),
              icon: _aiBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI check'),
              style: TextButton.styleFrom(
                  foregroundColor: _teal, visualDensity: VisualDensity.compact),
            ),
            TextButton.icon(
              onPressed: () => _showAddDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add habit'),
              style: TextButton.styleFrom(
                  foregroundColor: _accent, visualDensity: VisualDensity.compact),
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
                label: _dayLabel(_selected).toUpperCase(),
                verified: dueToday.where((h) => verified(h, dayKey0)).length,
                missed: [for (final h in dueToday) if (!done(h, dayKey0)) h]),
            const SizedBox(height: 12),
            _budgetCard(habits),
            const SizedBox(height: 12),
            if (dueToday.isNotEmpty) _dayTimeline(context, ref, dueToday, done, dayKey0),
            const SizedBox(height: 12),
            Text(_dayLabel(_selected).toUpperCase(),
                style: const TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const SizedBox(height: 6),
            if (dueToday.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nothing scheduled this day — enjoy the rest.',
                    style: TextStyle(color: _muted, fontSize: 13)),
              )
            else
              for (final h in dueToday)
                _habitTile(context, ref, h,
                    day: dayKey0,
                    done: done(h, dayKey0),
                    streak: currentStreak(_doneDaysOf(h, done)),
                    status: verified(h, dayKey0)
                        ? HabitStatus.verified
                        : ((st.completions[h.id]?.contains(dayKey0) ?? false)
                            ? HabitStatus.manual
                            : HabitStatus.notDone),
                    aiJudged: st.aiVerdictFor(h.id, dayKey0) != null,
                    measuredToday: measured(h, dayKey0),
                    last7: lastNDays(7),
                    doneDays: _doneDaysOf(h, done)),
            // Habits scheduled on other days only — for awareness.
            for (final h in (habits.where((h) => !isDueOn(h, _selected)).toList()..sort(byTime)))
              _habitTile(context, ref, h,
                  day: dayKey0,
                  done: done(h, dayKey0), streak: currentStreak(_doneDaysOf(h, done)),
                  status: HabitStatus.notDone, aiJudged: false,
                  measuredToday: null, last7: lastNDays(7),
                  doneDays: _doneDaysOf(h, done), dimmed: true),
          ],
        ],
      ),
    );
  }

  // Run the LLM verification for the shown day and refresh the roster.
  Future<void> _aiVerify(BuildContext context, WidgetRef ref) async {
    setState(() => _aiBusy = true);
    final api = ref.read(apiClientProvider);
    final Repository repo = ref.read(repositoryProvider);
    int? judged;
    try {
      await api.loadPersistedToken();
      judged = api.isSignedIn
          ? await runAiVerification(api, repo, date: _selected)
          : null;
    } catch (_) {
      judged = null;
    }
    if (!context.mounted) return;
    setState(() => _aiBusy = false);
    ref.read(habitsProvider.notifier).reload();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(judged == null
            ? 'AI check unavailable — sign in (☁) and make sure the AI key is set.'
            : judged == 0
                ? 'No auto-verifiable habits due this day.'
                : 'AI checked $judged habit${judged == 1 ? '' : 's'} against the day\'s data.')));
  }

  // Days counted "done" over the last 60 (auto habits = data-earned, manual = ticked).
  Set<String> _doneDaysOf(Habit h, bool Function(Habit, String) done) =>
      {for (final day in lastNDays(60)) if (done(h, day)) day};

  // ── The day's accountability recap: done / total · verified, + what's still missed ──
  Widget _summaryCard(int done, int total,
      {required String label, required int verified, required List<Habit> missed}) {
    final frac = total == 0 ? 0.0 : done / total;
    final allDone = done == total && total > 0;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
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

  // ── Day timeline: a Google-Calendar-style hour grid with habit blocks placed by
  // time. Overlapping habits split into side-by-side columns (interval partitioning,
  // like Google Calendar) instead of stacking on top of each other. ──
  Widget _dayTimeline(BuildContext context, WidgetRef ref, List<Habit> due,
      bool Function(Habit, String) done, String dayKey0) {
    int hourOf(Habit h) => int.tryParse(h.time!.split(':').first) ?? 0;
    int minOf(Habit h) {
      final p = h.time!.split(':');
      return p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
    }
    int startMin(Habit h) => hourOf(h) * 60 + minOf(h);
    int endMin(Habit h) =>
        startMin(h) + (h.durationMins > 0 ? h.durationMins : 30);
    final timed = [for (final h in due) if (h.time != null) h]..sort((a, b) => a.time!.compareTo(b.time!));
    final untimed = [for (final h in due) if (h.time == null) h];
    final now = DateTime.now();

    // Column assignment: group overlapping blocks into clusters, then greedily
    // place each block in the first column whose last block has ended.
    final colOf = <String, int>{}; // habit id → column
    final colsOf = <String, int>{}; // habit id → columns in its cluster
    var cluster = <Habit>[];
    var colEnds = <int>[];
    var clusterEnd = -1;
    void closeCluster() {
      for (final h in cluster) {
        colsOf[h.id] = colEnds.length;
      }
      cluster = <Habit>[];
      colEnds = <int>[];
    }
    for (final h in timed) {
      if (cluster.isNotEmpty && startMin(h) >= clusterEnd) closeCluster();
      var placed = false;
      for (var c = 0; c < colEnds.length; c++) {
        if (startMin(h) >= colEnds[c]) {
          colOf[h.id] = c;
          colEnds[c] = endMin(h);
          placed = true;
          break;
        }
      }
      if (!placed) {
        colOf[h.id] = colEnds.length;
        colEnds.add(endMin(h));
      }
      cluster.add(h);
      clusterEnd = math.max(clusterEnd, endMin(h));
    }
    closeCluster();

    const hourH = 44.0;
    const gutter = 42.0;
    // Window the grid to the habits (clamped to a sensible 6am–10pm default span).
    var startH = 6, endH = 22;
    if (timed.isNotEmpty) {
      startH = math.min(startH, timed.map(hourOf).reduce(math.min));
      endH = math.max(endH,
          timed.map((h) => hourOf(h) + ((h.durationMins > 0 ? h.durationMins : 30) / 60).ceil()).reduce(math.max));
    }
    endH = math.min(24, endH);
    final rows = endH - startH;

    Widget block(Habit h, double areaW) {
      final isDone = done(h, dayKey0);
      final c = Color(sectionOf(h.section).color);
      final top = (hourOf(h) - startH + minOf(h) / 60.0) * hourH;
      final height = math.max(26.0, (h.durationMins > 0 ? h.durationMins : 30) / 60.0 * hourH - 3);
      final cols = colsOf[h.id] ?? 1;
      final col = colOf[h.id] ?? 0;
      final colW = (areaW - gutter - 12) / cols;
      final narrow = colW < 90; // drop the emoji when columns get tight
      return Positioned(
        top: top,
        left: gutter + 6 + col * colW,
        width: colW - (cols > 1 ? 3 : 0),
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: h.verify == 'manual'
                ? () => ref.read(habitsProvider.notifier).toggleOn(h.id, dayKey0)
                : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(seconds: 2),
                    content: Text('"${h.title}" counts only from real data (watch/sets/food).'))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.withValues(alpha: isDone ? 0.28 : 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: c, width: 3)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                      narrow ? h.title : '${sectionOf(h.section).emoji} ${h.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: narrow ? 11 : 12, fontWeight: FontWeight.w700,
                          color: isDone ? _muted : Colors.white,
                          decoration: isDone ? TextDecoration.lineThrough : null)),
                ),
                if (isDone && !narrow)
                  const Icon(Icons.check_circle, color: _teal, size: 15),
              ]),
            ),
          ),
        ),
      );
    }

    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('TIMELINE', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const Spacer(),
            if (untimed.isNotEmpty)
              Text('${untimed.length} anytime', style: const TextStyle(fontSize: 10.5, color: _muted)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: rows * hourH,
            child: LayoutBuilder(
              builder: (ctx, box) => Stack(children: [
                // Hour gridlines + labels.
                for (var i = 0; i <= rows; i++)
                  Positioned(
                    top: i * hourH, left: 0, right: 0,
                    child: Row(children: [
                      SizedBox(width: gutter,
                          child: Text(_hourLabel(startH + i),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 9.5, color: _muted))),
                      const SizedBox(width: 6),
                      Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.06))),
                    ]),
                  ),
                // "Now" line — only meaningful when viewing today.
                if (dayKey0 == todayKey() && now.hour >= startH && now.hour < endH)
                  Positioned(
                    top: (now.hour - startH + now.minute / 60.0) * hourH, left: gutter, right: 0,
                    child: Row(children: [
                      Container(width: 6, height: 6,
                          decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle)),
                      Expanded(child: Container(height: 1.5, color: _teal.withValues(alpha: 0.6))),
                    ]),
                  ),
                for (final h in timed) block(h, box.maxWidth),
              ]),
            ),
          ),
          if (untimed.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final h in untimed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(sectionOf(h.section).color).withValues(alpha: done(h, dayKey0) ? 0.28 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${sectionOf(h.section).emoji} ${h.title}${done(h, dayKey0) ? ' ✓' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  static String _hourLabel(int h) {
    final hh = h % 24;
    final ampm = hh < 12 ? 'a' : 'p';
    final h12 = hh % 12 == 0 ? 12 : hh % 12;
    return '$h12$ampm';
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
      {required String day,
      required bool done,
      required int streak,
      required HabitStatus status,
      required bool aiJudged,
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
            // Long-press to edit any habit (title, target, time, days…).
            onLongPress: () => _showAddDialog(context, ref, edit: h),
            // Manual habits toggle on tap. Data-verifiable ones are STRICT:
            // only real evidence counts (watch session, logged sets, food
            // totals) — that's what keeps the AI's picture honest.
            onTap: dimmed
                ? null
                : (h.verify == 'manual'
                    ? () => ref.read(habitsProvider.notifier).toggleOn(h.id, day)
                    : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        duration: const Duration(seconds: 3),
                        content: Text('"${h.title}" counts only from real data — '
                            'train with the watch / log the sets or food, then sync. '
                            'The AI check verifies it.')))),
            child: IntrinsicHeight(
              child: Row(children: [
                Container(width: 4, color: cc),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(children: [
                      Icon(
                          done
                              ? Icons.check_circle
                              : (h.verify == 'manual' ? Icons.circle_outlined : Icons.sensors),
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
                        _badge(aiJudged ? '✨ AI verified' : '✓ verified', _teal)
                      else if (streak > 0)
                        _badge('🔥 $streak', _accent),
                      // The habit carries its workout plan → one tap starts the
                      // session pre-filled; log what actually happened.
                      if (h.templateId != null && !done && day == todayKey())
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 22, color: _teal,
                          tooltip: 'Start planned workout',
                          icon: const Icon(Icons.play_circle_outline),
                          onPressed: () => _startPlanned(context, ref, h),
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18, color: _muted,
                        tooltip: 'Edit habit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showAddDialog(context, ref, edit: h),
                      ),
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
        if (h.templateId != null) _pill('🏋 planned workout', _teal),
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

  // Start the habit's planned workout: a new session pre-filled from its
  // template, opened for logging what actually happened.
  void _startPlanned(BuildContext context, WidgetRef ref, Habit h) {
    final t = ref
        .read(templatesProvider)
        .where((t) => t.id == h.templateId)
        .firstOrNull;
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This habit\'s workout plan was deleted — edit the habit to pick a new one.')));
      return;
    }
    final s = ref.read(workoutProvider.notifier).createFromTemplate(t);
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SessionDetailScreen(sessionId: s.id)));
  }

  // Write habits straight into the user's Google Calendar via the Calendar API (upsert +
  // prune, no duplicates). Needs the calendar scope — prompts a reconnect if missing.
  Future<void> _pushCalendar(BuildContext context, WidgetRef ref) async {
    setState(() => _calBusy = true);
    final habits = [for (final h in ref.read(habitsProvider).habits) h.toJson()];
    String? tz;
    try {
      tz = await FlutterTimezone.getLocalTimezone();
    } catch (_) {/* fall back to floating times */}
    String msg;
    try {
      final r = await ref.read(apiClientProvider).pushCalendar(habits, tz);
      final n = (r['added'] ?? 0) + (r['updated'] ?? 0);
      final failed = (r['failed'] ?? 0) as num;
      final deduped = (r['deduped'] ?? 0) as num;
      msg = '$n habit${n == 1 ? '' : 's'} synced to Google Calendar'
          '${deduped > 0 ? ' · $deduped duplicate${deduped == 1 ? '' : 's'} cleaned' : ''}'
          '${(r['removed'] ?? 0) != 0 ? ' · ${r['removed']} removed' : ''}'
          '${failed > 0 ? ' · $failed failed: ${(r['error'] ?? '').toString().replaceAll('\n', ' ')}' : ''}.';
    } on ApiException catch (e) {
      msg = e.status == 412 || e.message.contains('calendar_api_disabled')
          ? 'The Google Calendar API is disabled for your Cloud project — enable it at '
            'console.cloud.google.com → APIs & Services → Library → Google Calendar API.'
          : (e.status == 401 || e.status == 403)
              ? 'Connect Google Calendar in the Cloud sheet (☁), then try again.'
              : 'Calendar sync failed — try again in a moment.';
    } catch (_) {
      msg = 'Couldn’t reach the calendar service.';
    }
    if (!context.mounted) return;
    setState(() => _calBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Add OR edit a habit: section → preset (or custom) → cadence/time/duration.
  // Pass [edit] to modify an existing habit in place (same id, same history). ──
  Future<void> _showAddDialog(BuildContext context, WidgetRef ref, {Habit? edit}) async {
    String section = edit?.section ?? 'sleep';
    HabitPreset? preset;
    final titleCtrl = TextEditingController(text: edit?.title ?? '');
    final durCtrl = TextEditingController(
        text: (edit?.durationMins ?? 0) > 0 ? '${edit!.durationMins}' : '');
    final costCtrl = TextEditingController(
        text: (edit?.cost ?? 0) > 0
            ? (edit!.cost == edit.cost.roundToDouble()
                ? '${edit.cost.round()}'
                : '${edit.cost}')
            : '');
    final targetCtrl = TextEditingController(
        text: edit?.target == null
            ? ''
            : (edit!.target == edit.target!.roundToDouble()
                ? '${edit.target!.round()}'
                : '${edit.target}'));
    final productsCtrl = TextEditingController(text: edit?.products.join(', ') ?? '');
    String compare = edit?.compare ?? 'gte';
    String? goalKey = edit?.goalKey;
    String unit = edit?.unit ?? '';
    String? templateId = edit?.templateId;
    String? time = edit?.time;
    String cadence = edit?.cadence ?? 'daily';
    final days = <int>{...?edit?.days};

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final presets = presetsFor(section);
          return AlertDialog(
            backgroundColor: _card,
            title: Text(edit == null ? 'New habit' : 'Edit habit'),
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
                // Quantitative target — only for auto-measured sections. Direction
                // (≥ / ≤) comes from the preset (calories/body-fat presets are
                // "stay under"); the AI verifier judges custom habits semantically,
                // so there's nothing else to configure.
                if (section != 'aesthetics' && section != 'misc') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: targetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          'Target (optional)${unit.isEmpty ? '' : ' · ${compare == 'lte' ? 'stay under' : 'reach'} $unit'}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                // Exercise: the habit can CARRY its workout plan (a saved template) —
                // on due days it starts pre-filled from the Habits tab.
                if (section == 'exercise') ...[
                  const SizedBox(height: 10),
                  const Text('Workout plan (starts pre-filled on due days)',
                      style: TextStyle(fontSize: 11, color: _muted)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    ChoiceChip(
                      label: const Text('None'),
                      selected: templateId == null,
                      onSelected: (_) => setLocal(() => templateId = null),
                    ),
                    for (final t in ref.read(templatesProvider))
                      ChoiceChip(
                        label: Text('${t.name} · ${t.setCount} sets'),
                        selected: templateId == t.id,
                        selectedColor: _teal.withValues(alpha: 0.25),
                        onSelected: (_) => setLocal(() => templateId = t.id),
                      ),
                    // Build a plan right here — the editor pops with the new id.
                    ActionChip(
                      label: const Text('➕ New plan…'),
                      onPressed: () async {
                        final id = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                                builder: (_) => TemplateEditorScreen(
                                    suggestedName: titleCtrl.text.trim())));
                        if (id != null) setLocal(() => templateId = id);
                      },
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
                    flex: 3,
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
                    flex: 2,
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
                  final products = section == 'aesthetics'
                      ? [for (final p in productsCtrl.text.split(',')) if (p.trim().isNotEmpty) p.trim()]
                      : const <String>[];
                  if (edit != null && titleCtrl.text.trim().isNotEmpty) {
                    // Edit in place: same id + createdAt, so streaks/history stay.
                    // Picking a preset can re-link the verification rule.
                    ref.read(habitsProvider.notifier).updateHabit(Habit(
                          id: edit.id,
                          title: titleCtrl.text.trim(),
                          section: section,
                          verify: preset?.verify ?? edit.verify,
                          linkedMetricId: preset?.linkedMetricId ?? edit.linkedMetricId,
                          target: double.tryParse(targetCtrl.text.trim()),
                          compare: compare,
                          goalKey: goalKey,
                          unit: unit,
                          products: products,
                          templateId: section == 'exercise' ? templateId : null,
                          time: time,
                          durationMins: int.tryParse(durCtrl.text) ?? 0,
                          cost: double.tryParse(costCtrl.text.trim()) ?? 0,
                          cadence: cadence,
                          days: cadence == 'weekly' ? days.toList() : const [],
                          createdAt: edit.createdAt,
                        ));
                  } else {
                    final verify = preset?.verify ??
                        (section == 'exercise' ? 'workout' : section == 'diet' ? 'diet' : 'manual');
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
                          templateId: section == 'exercise' ? templateId : null,
                          time: time,
                          durationMins: int.tryParse(durCtrl.text) ?? 0,
                          cost: double.tryParse(costCtrl.text.trim()) ?? 0,
                          cadence: cadence,
                          days: cadence == 'weekly' ? days.toList() : const [],
                        );
                  }
                  Navigator.pop(ctx);
                },
                child: Text(edit == null ? 'Add' : 'Save'),
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
