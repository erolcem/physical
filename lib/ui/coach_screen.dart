// ui/coach_screen.dart — the AI Coach tab (PDF Part 5). A chat with Physical's
// coach; the backend feeds Gemini the user's real ranks (its data) plus the live
// habits + profile this tab sends. Requires sign-in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart';
import '../data/coach_context.dart';
import '../data/diet.dart' show todayDiet;
import '../data/habits.dart' show habitSections, sectionOf;
import '../data/metrics.dart' show metricById, metrics, MetricTier;
import '../data/readiness.dart' show dailyReadiness;
import '../data/sync.dart' show apiClientProvider;
import '../data/workout.dart'
    show SetMode, WorkoutSet, WorkoutTemplate, exercisesOverDays, sessionsOverDays,
        sortedByRecent, volumeOverDays;
import '../state/habit_providers.dart';
import '../state/log_providers.dart';
import '../state/providers.dart'
    show categoryRanksProvider, currentBodyweightProvider, latestLogsProvider, logsProvider, overallProvider;

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
const _teal = Color(0xFF4CE0C3);
const _muted = Color(0xFF7880A8);

// A fixed selection of coach functions (PDF Table 3) — keeps responses robust and
// on-rails. Each is sent as a structured prompt the coach answers over your data.
const _coachFunctions = <(String, String)>[
  ('🌅 Morning brief', 'Give me my morning brief: today\'s readiness, what\'s scheduled on my habit checklist, what to prioritise given my recovery + weakest areas, and one thing to watch out for. Keep it tight and actionable.'),
  ('🌙 Evening digest', 'Give me my evening digest: go through today\'s habits (which were completed vs missed — the completion data includes the AI verification results), today\'s training, diet and recovery numbers vs my targets, name what went well and what slipped, and take the initiative: propose any habit changes, target adjustments or amendments for tomorrow based on the data.'),
  ('😴 Sleep review', 'Review my sleep & recovery from my recent data and habits, then give 2–3 specific suggestions.'),
  ('🥗 Diet review', 'Review my diet — calories, protein and macros vs my weight/body-fat — and suggest concrete adjustments.'),
  ('💪 Training review', 'Review my training: recent volume, sessions, and which lifts/ranks lag. What should I prioritise this week?'),
  ('✨ Aesthetics', 'Review my aesthetics routine and scores; suggest evidence-based improvements for skin/hair/oral health.'),
  ('🔗 Find correlations', 'Analyse my day-aligned correlations: surface the strongest real patterns in my data, explain the likely mechanism, state the causation caveat and the sample size, and suggest one experiment to test the most useful one — then pin it.'),
  ('🗓 Weekly review', 'Give me a disciplined weekly review across sleep, training, diet, recovery and habit adherence: cite the numbers, name what improved vs regressed, identify the single biggest issue, and set my plan + habit adjustments for next week.'),
  ('🎯 Set a goal', 'Help me set one emphasised goal: ask what I want to prioritise, then tailor my habits and targets toward it.'),
  ('🏆 My progress', 'Discuss my progress and any milestones across my ranks and trends — what to celebrate and what is next.'),
  ('📈 What should I improve?', 'Across all my data, what is my single highest-leverage thing to improve right now, and exactly how?'),
];

class _Msg {
  final String role; // 'user' | 'model'
  final String text;
  final List<Map<String, dynamic>> actions; // confirmable habit changes
  _Msg(this.role, this.text, {this.actions = const []});
}

class CoachTab extends ConsumerStatefulWidget {
  const CoachTab({super.key});
  @override
  ConsumerState<CoachTab> createState() => _CoachTabState();
}

class _CoachTabState extends ConsumerState<CoachTab>
    with AutomaticKeepAliveClientMixin {
  // Keep the chat alive across tab switches so the conversation persists for the session.
  @override
  bool get wantKeepAlive => true;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _loading = true, _signedIn = false, _configured = false, _sending = false;
  int? _age; // auto-ported from the Google Health profile (no manual profile page)

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.loadPersistedToken();
      if (!api.isSignedIn) {
        if (mounted) setState(() { _signedIn = false; _loading = false; });
        return;
      }
      final st = await api.coachStatus();
      final age = await api.googleProfileAge(); // one fetch per coach session
      if (mounted) {
        setState(() {
          _signedIn = true;
          _configured = st['configured'] == true;
          _age = age;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _signedIn = true; _configured = false; _loading = false; });
    }
  }

  // Rich habit context: target, measured-vs-target, met, streak, adherence, products.
  List<Map<String, dynamic>> _habitsCtx() {
    final hs = ref.read(habitsProvider);
    return coachHabits(hs.habits, hs.completions,
        logs: ref.read(logsProvider),
        food: ref.read(dietProvider),
        workouts: ref.read(workoutProvider),
        aiVerdicts: hs.aiVerdicts);
  }

  // App-computed ranks (the app holds the full data + canonical engine), or null if empty.
  Map<String, dynamic>? _ranksCtx() {
    final latest = ref.read(latestLogsProvider);
    if (latest.isEmpty) return null;
    final cats = ref.read(categoryRanksProvider);
    return coachRanks(
      overall: ref.read(overallProvider),
      categories: {for (final e in cats.entries) e.key: e.value},
      latest: latest,
      logs: ref.read(logsProvider),
    );
  }

  Map<String, dynamic> _trendsCtx() => coachTrends(ref.read(logsProvider));
  List<Map<String, dynamic>> _correlationsCtx() => coachCorrelations(ref.read(logsProvider));
  List<Map<String, dynamic>> _setsCtx() => coachWorkoutSets(ref.read(workoutProvider));
  // Full per-metric history (all metrics incl. background) + energy balance, so the coach
  // sees the raw data over time and can make its own connections.
  Map<String, List<double>> _historyCtx() => coachHistory(ref.read(logsProvider));
  Map<String, dynamic> _energyCtx() {
    final latest = ref.read(latestLogsProvider);
    return coachEnergy(ref.read(dietProvider), ref.read(workoutProvider),
        weightKg: ref.read(currentBodyweightProvider),
        heightCm: latest['height']?.value, age: _age);
  }

  // Local, LLM-free insights for the welcome screen (instant + offline).
  List<({String title, String body, String ask})> _insights() => coachInsights(
        correlations: _correlationsCtx(),
        ranks: _ranksCtx(),
        trends: _trendsCtx(),
        habits: _habitsCtx(),
        readiness: dailyReadiness(ref.read(logsProvider), ref.read(workoutProvider)),
      );

  // Stats are auto-sourced (no manual profile page): age from Google, height/weight/
  // body-fat from synced logs. Gender defaults to the app's young-male cohort.
  Map<String, dynamic> _profileCtx() {
    final latest = ref.read(latestLogsProvider);
    final weight = ref.read(currentBodyweightProvider);
    final height = latest['height']?.value;
    final bodyFat = latest['body_fat_pct']?.value;
    return {
      if (_age != null) 'age': _age,
      'gender': 'male',
      if (height != null) 'heightCm': height,
      if (weight != null) 'weightKg': weight,
      if (bodyFat != null) 'bodyFatPct': bodyFat,
    };
  }

  // The actual meals of the last week (names + macros) — food quality/timing,
  // not just totals.
  List<Map<String, dynamic>> _mealsCtx() => coachMeals(ref.read(dietProvider));

  Map<String, dynamic> _dietCtx() {
    final t = todayDiet(ref.read(dietProvider));
    return {
      'calories': t.calories, 'protein': t.protein,
      'carbs': t.carbs, 'fat': t.fat, 'fibre': t.fibre, 'items': t.items,
      if (t.micros.values.any((v) => v > 0)) 'micros': t.micros,
    };
  }

  Map<String, dynamic> _trainingCtx() {
    final w = ref.read(workoutProvider);
    final recent = sortedByRecent(w);
    return {
      'weekly_volume': volumeOverDays(w).round(),
      'sessions': sessionsOverDays(w),
      'exercises': exercisesOverDays(w).toList(), // free-text exercise names
      'types': {for (final s in recent.take(15)) s.type}.toList(),
      if (recent.isNotEmpty) 'last_type': recent.first.type,
    };
  }

  Map<String, dynamic> _aestheticsCtx() {
    final latest = ref.read(latestLogsProvider);
    final out = <String, dynamic>{};
    for (final m in metrics) {
      if (m.category != 'aesthetics' || m.tier != MetricTier.tracked) continue;
      final l = latest[m.id];
      if (l != null) out[m.label] = l.value;
    }
    return out;
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    final api = ref.read(apiClientProvider);
    final history = [for (final m in _messages) {'role': m.role, 'text': m.text}];
    setState(() {
      _messages.add(_Msg('user', text));
      _sending = true;
      _input.clear();
    });
    _scrollToBottom();
    try {
      final res = await api.coachChat(
          message: text, history: history, habits: _habitsCtx(), profile: _profileCtx(),
          diet: _dietCtx(), training: _trainingCtx(), aesthetics: _aestheticsCtx(),
          ranks: _ranksCtx(), trends: _trendsCtx(),
          correlations: _correlationsCtx(), workoutSets: _setsCtx(),
          metricHistory: _historyCtx(), energy: _energyCtx(), meals: _mealsCtx());
      final reply = (res['reply'] as String?) ?? '';
      final actions =
          ((res['actions'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _messages.add(_Msg('model', reply, actions: actions)));
    } on ApiException catch (e) {
      if (mounted) {
        // Surface a short server detail so a persistent failure is diagnosable.
        final detail = e.message.replaceAll('\n', ' ').trim();
        final hint = detail.isEmpty || detail.length > 180
            ? '' : '\n($detail)';
        setState(() => _messages.add(_Msg('model',
            e.status == 503
                ? "I'm not set up on the server yet — add a GEMINI_API_KEY and I'll be right here."
                : "That one didn't go through — tap send to retry (your message is still in the box).$hint")));
        // Keep the user's text so a retry is one tap away.
        _input.text = text;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _messages.add(_Msg('model',
            "Couldn't reach the coach — check your connection and tap send to retry.")));
        _input.text = text;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _showFunctions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Coach functions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('🗓 Plan my week (AI builds your habits)'),
              onTap: () {
                Navigator.pop(ctx);
                _planWeek();
              },
            ),
            for (final f in _coachFunctions)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(f.$1),
                onTap: () {
                  Navigator.pop(ctx);
                  _send(f.$2);
                },
              ),
          ]),
        ),
      ),
    );
  }

  // ── "Plan my week": the AI designs a complete scaffolded habit roster (with
  // workout plans) from the user's data + an optional emphasised goal; the user
  // reviews and applies it — nothing changes without their tap. ──
  Future<void> _planWeek() async {
    final goalCtrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Plan my week'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'The coach reads your ranks, recovery, diet and training history and '
              'proposes a full weekly habit roster — including the workout plans your '
              'gym habits will carry. You review everything before it\'s added.',
              style: TextStyle(fontSize: 13, color: _muted)),
          const SizedBox(height: 12),
          TextField(
            controller: goalCtrl,
            decoration: const InputDecoration(
                labelText: 'Goal to emphasise (optional)',
                hintText: 'e.g. cut to 12% body fat, bigger bench…',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Build plan')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _sending = true);
    Map<String, dynamic>? plan;
    String? error;
    try {
      plan = await ref.read(apiClientProvider).coachPlan(
          goal: goalCtrl.text.trim(),
          habits: _habitsCtx(), profile: _profileCtx(), diet: _dietCtx(),
          training: _trainingCtx(), aesthetics: _aestheticsCtx(), ranks: _ranksCtx(),
          trends: _trendsCtx(), correlations: _correlationsCtx(), workoutSets: _setsCtx(),
          metricHistory: _historyCtx(), energy: _energyCtx(), meals: _mealsCtx());
    } on ApiException catch (e) {
      error = e.status == 503
          ? 'The AI coach isn\'t configured on the server yet.'
          : 'The coach couldn\'t build a plan — try again in a moment.';
    } catch (_) {
      error = 'Couldn\'t reach the coach — check your connection.';
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (plan == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'No plan.')));
      return;
    }
    _showPlanReview(plan);
  }

  void _showPlanReview(Map<String, dynamic> plan) {
    final proposals = ((plan['habits'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final selected = List<bool>.filled(proposals.length, true);
    var replace = false; // remove the current roster before applying
    String planLine(Map<String, dynamic> h) {
      final bits = <String>[];
      if (h['target'] != null) {
        bits.add('${h['compare'] == 'lte' ? '≤' : '≥'} ${h['target']}${h['unit'] ?? ''}');
      }
      if (h['time'] != null) bits.add('⏰ ${h['time']}');
      if (h['cadence'] == 'weekly' && h['days'] != null) {
        const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        bits.add((h['days'] as List).map((d) => wd[(d as num).toInt() - 1]).join(' '));
      }
      final p = h['plan'] as Map<String, dynamic>?;
      if (p != null) {
        final names = {for (final s in (p['sets'] as List? ?? const [])) (s as Map)['name']};
        bits.add('🏋 ${names.length} exercises · ${(p['sets'] as List? ?? const []).length} sets');
      }
      return bits.join(' · ');
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your proposed week',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                if ((plan['summary'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(plan['summary'] as String,
                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                ],
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: proposals.length,
                    itemBuilder: (_, i) {
                      final h = proposals[i];
                      final sec = sectionOf((h['section'] as String?) ?? 'misc');
                      final detail = planLine(h);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: selected[i],
                        onChanged: (v) => setLocal(() => selected[i] = v ?? false),
                        title: Text('${sec.emoji} ${h['title']}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        subtitle: detail.isEmpty
                            ? null
                            : Text(detail, style: const TextStyle(fontSize: 11.5, color: _muted)),
                      );
                    },
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: replace,
                  onChanged: (v) => setLocal(() => replace = v ?? false),
                  title: const Text('Replace my current habits',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                      'Removes every existing habit (and its streaks) first — a fresh start.',
                      style: TextStyle(fontSize: 11, color: _muted)),
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: _accent, minimumSize: const Size.fromHeight(46)),
                  icon: const Icon(Icons.check),
                  label: Text(
                      '${replace ? 'Replace with' : 'Add'} ${selected.where((s) => s).length} habits'),
                  onPressed: () {
                    if (replace) {
                      final notifier = ref.read(habitsProvider.notifier);
                      for (final h in [...ref.read(habitsProvider).habits]) {
                        notifier.removeHabit(h.id);
                      }
                    }
                    var added = 0;
                    for (var i = 0; i < proposals.length; i++) {
                      if (!selected[i]) continue;
                      _applyProposal(proposals[i]);
                      added++;
                    }
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '${replace ? 'Roster replaced —' : 'Added'} $added habits, see the Habits tab.')));
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // Monotonic uniquifier — proposals apply in a tight loop and microsecond
  // timestamps can collide (an id collision silently overwrites a template).
  static int _planSeq = 0;

  // One proposal → (optionally) its workout template + the habit carrying it.
  void _applyProposal(Map<String, dynamic> h) {
    String? templateId;
    final p = h['plan'] as Map<String, dynamic>?;
    if (p != null) {
      final sets = [
        for (final s in ((p['sets'] as List?) ?? const []).cast<Map<String, dynamic>>())
          WorkoutSet(
            name: (s['name'] as String?) ?? 'Exercise',
            mode: s['w'] != null ? SetMode.weightReps : SetMode.reps,
            weight: (s['w'] as num?)?.toDouble(),
            reps: (s['r'] as num?)?.toInt(),
          )
      ];
      final t = WorkoutTemplate(
        id: '${DateTime.now().microsecondsSinceEpoch}-p${_planSeq++}',
        name: (p['name'] as String?) ?? (h['title'] as String? ?? 'Workout'),
        type: (p['type'] as String?) ?? 'Weightlifting',
        sets: sets,
      );
      ref.read(templatesProvider.notifier).save(t);
      templateId = t.id;
    }
    final section = habitSections.containsKey(h['section']) ? h['section'] as String : 'misc';
    ref.read(habitsProvider.notifier).addHabit(
          (h['title'] as String?) ?? 'Habit',
          section: section,
          verify: h['verify'] as String?,
          linkedMetricId: h['metric'] as String?,
          target: (h['target'] as num?)?.toDouble(),
          compare: (h['compare'] as String?) ?? 'gte',
          goalKey: h['goalKey'] as String?,
          unit: (h['unit'] as String?) ?? '',
          templateId: templateId,
          time: h['time'] as String?,
          durationMins: (h['durationMins'] as num?)?.toInt() ?? 0,
          cadence: (h['cadence'] as String?) ?? 'daily',
          days: [for (final d in ((h['days'] as List?) ?? const [])) (d as num).toInt()],
        );
  }

  Future<void> _showContext() async {
    final api = ref.read(apiClientProvider);
    final habits = _habitsCtx();
    final profile = _profileCtx();
    final diet = _dietCtx();
    final training = _trainingCtx();
    final aesthetics = _aestheticsCtx();
    final ranks = _ranksCtx();
    final trends = _trendsCtx();
    final correlations = _correlationsCtx();
    final sets = _setsCtx();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => FutureBuilder<Map<String, dynamic>>(
        future: api.coachContext(
            habits: habits, profile: profile, diet: diet, training: training, aesthetics: aesthetics,
            ranks: ranks, trends: trends, correlations: correlations, workoutSets: sets),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
          }
          if (!snap.hasData) {
            return const SizedBox(
                height: 160,
                child: Center(child: Text("Couldn't load the context.",
                    style: TextStyle(color: _muted))));
          }
          return _contextSheet(snap.data!);
        },
      ),
    );
  }

  Widget _contextSheet(Map<String, dynamic> c) {
    final cats = (c['categories'] as Map?) ?? const {};
    final recent = (c['recent'] as Map?) ?? const {};
    final habits = ((c['habits'] as List?) ?? const []).cast<String>();
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 96, child: Text(label, style: const TextStyle(color: _muted, fontSize: 12))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        );
    return SafeArea(
      child: ConstrainedBox(
        // Cap the sheet so long context (trends, correlations, sets…) scrolls instead of
        // overflowing the screen.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('What your coach sees',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (c['profile'] != null) row('Profile', c['profile'] as String),
          if (c['overall'] != null) row('Overall', c['overall'] as String),
          if (c['coverage'] != null) row('Coverage', c['coverage'] as String),
          if (cats.isNotEmpty)
            row('Categories', cats.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
          if (c['weakest'] != null) row('Weakest', c['weakest'] as String),
          if (c['strongest'] != null) row('Strongest', c['strongest'] as String),
          if (recent.isNotEmpty)
            row('Recent', recent.entries.map((e) => '${e.key}: ${e.value}').join(', ')),
          if (c['trends'] != null) row('Trends', c['trends'] as String),
          if (c['correlations'] != null) row('Correlations', c['correlations'] as String),
          if (c['diet'] != null) row('Diet', c['diet'] as String),
          if (c['training'] != null) row('Training', c['training'] as String),
          if (c['sets'] != null) row('Sets', c['sets'] as String),
          if (c['aesthetics'] != null) row('Aesthetics', c['aesthetics'] as String),
          row('Habits', habits.isEmpty ? '—' : habits.join('\n')),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _card, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.lock_outline, color: _teal, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text((c['note'] as String?) ?? '',
                  style: const TextStyle(fontSize: 11.5, color: _muted))),
            ]),
          ),
          ]),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return Container(
      color: _bg,
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_signedIn
                ? _notice(Icons.lock_outline,
                    'Sign in via Cloud Sync (☁) to chat with your coach.')
                : !_configured
                    ? _notice(Icons.auto_awesome_outlined,
                        'The AI coach isn’t set up on the server yet (needs a GEMINI_API_KEY).')
                    : _chat(),
      ),
    );
  }

  Widget _notice(IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: _muted, size: 44),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 14)),
          ]),
        ),
      );

  Widget _chat() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 6, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Your AI coach',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          Row(children: [
            TextButton.icon(
              onPressed: _showFunctions,
              icon: const Icon(Icons.auto_awesome_outlined, size: 15),
              label: const Text('Functions'),
              style: TextButton.styleFrom(foregroundColor: _accent, textStyle: const TextStyle(fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: _showContext,
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('What I see'),
              style: TextButton.styleFrom(foregroundColor: _muted, textStyle: const TextStyle(fontSize: 12)),
            ),
          ]),
        ]),
      ),
      Expanded(
        // Tap the conversation (or drag it) to dismiss the keyboard — fixes iOS where the
        // keyboard otherwise stays up with no way to close it.
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: _messages.isEmpty
              ? _welcome()
              : ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(14),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _messages.length) return _bubble(_Msg('model', '…'));
                    return _messageWidget(_messages[i]);
                  },
                ),
        ),
      ),
      _inputBar(),
    ]);
  }

  Widget _welcome() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.auto_awesome, color: _accent, size: 40),
          const SizedBox(height: 12),
          const Text('Your AI coach',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('I can see your ranks, recent recovery, and habits. Ask me anything.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 20),
          ..._insightCards(),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('🗓 Plan my week'),
                backgroundColor: _accent.withValues(alpha: 0.2),
                side: const BorderSide(color: _teal),
                labelStyle: const TextStyle(color: _teal, fontSize: 12, fontWeight: FontWeight.w700),
                onPressed: _planWeek,
              ),
              for (final f in _coachFunctions)
                ActionChip(
                  label: Text(f.$1),
                  backgroundColor: _card,
                  side: const BorderSide(color: _accent),
                  labelStyle: const TextStyle(color: _accent, fontSize: 12),
                  onPressed: () => _send(f.$2),
                ),
            ],
          ),
        ],
      );

  // Proactive insight cards on the welcome screen — tap to ask the coach about one.
  List<Widget> _insightCards() {
    final insights = _insights();
    if (insights.isEmpty) return const [];
    return [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text('INSIGHTS', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
      ),
      const SizedBox(height: 8),
      for (final i in insights)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _send(i.ask),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.title, style: const TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(i.body, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: _muted, size: 18),
                ]),
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
    ];
  }

  Widget _messageWidget(_Msg m) {
    if (m.actions.isEmpty) return _bubble(m);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _bubble(m),
      for (final a in m.actions) _actionCard(a),
    ]);
  }

  String _exLabel(String id) {
    try {
      return metricById(id).label;
    } catch (_) {
      return id;
    }
  }

  Widget _actionCard(Map<String, dynamic> a) {
    final applied = a['_applied'] == true;
    final type = a['type'];
    final title = a['title'] as String? ?? '';
    final String desc;
    final IconData icon;
    if (type == 'add_habit') {
      icon = Icons.add_circle_outline;
      desc = 'Add habit: $title'
          '${a['category'] != null ? ' · ${a['category']}' : ''}'
          '${a['durationMins'] != null ? ' · ${a['durationMins']}min' : ''}'
          '${a['time'] != null ? ' · ${a['time']}' : ''}';
    } else if (type == 'adjust_habit_target') {
      icon = Icons.tune;
      final cmp = a['compare'] == 'lte' ? '≤' : '≥';
      desc = 'Set target: $title $cmp ${a['target']}';
    } else if (type == 'pin_correlation') {
      icon = Icons.push_pin_outlined;
      desc = 'Pin insight: ${_exLabel(a['a'] as String? ?? '')} ↔ ${_exLabel(a['b'] as String? ?? '')}';
    } else {
      icon = Icons.remove_circle_outline;
      desc = 'Remove habit: $title';
    }
    return Container(
      margin: const EdgeInsets.only(top: 6, right: 40, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: _accent, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(desc, style: const TextStyle(fontSize: 12.5))),
        if (applied)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('Applied ✓',
                style: TextStyle(color: _teal, fontWeight: FontWeight.w700, fontSize: 12)),
          )
        else
          TextButton(
            onPressed: () => _applyAction(a),
            style: TextButton.styleFrom(foregroundColor: _accent),
            child: const Text('Apply'),
          ),
      ]),
    );
  }

  void _applyAction(Map<String, dynamic> a) {
    final notifier = ref.read(habitsProvider.notifier);
    if (a['type'] == 'add_habit') {
      notifier.addHabit(a['title'] as String,
          section: (a['category'] as String?) ?? 'misc',
          time: a['time'] as String?,
          durationMins: (a['durationMins'] as num?)?.toInt() ?? 0);
    } else if (a['type'] == 'adjust_habit_target') {
      notifier.adjustTarget(a['title'] as String? ?? '',
          (a['target'] as num?)?.toDouble() ?? 0, compare: a['compare'] as String?);
    } else if (a['type'] == 'remove_habit') {
      final title = (a['title'] as String? ?? '').toLowerCase();
      final hs = ref.read(habitsProvider);
      final match = hs.habits.where((h) => h.title.toLowerCase() == title);
      if (match.isNotEmpty) notifier.removeHabit(match.first.id);
    } else if (a['type'] == 'pin_correlation') {
      final am = a['a'] as String?, bm = a['b'] as String?;
      if (am != null && bm != null &&
          metrics.any((m) => m.id == am) && metrics.any((m) => m.id == bm)) {
        ref.read(pinsProvider.notifier).add(am, bm);
      }
    }
    setState(() => a['_applied'] = true);
  }

  Widget _bubble(_Msg m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? _accent : _card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(m.text,
            style: TextStyle(
                color: isUser ? Colors.white : const Color(0xFFE6E8F2), fontSize: 14, height: 1.35)),
      ),
    );
  }

  Widget _inputBar() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
            color: _bg, border: Border(top: BorderSide(color: Color(0x14FFFFFF)))),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _sending ? null : _send,
              decoration: InputDecoration(
                hintText: 'Ask your coach…',
                filled: true,
                fillColor: _card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: _accent,
            child: IconButton(
              icon: const Icon(Icons.arrow_upward, color: Colors.white),
              onPressed: _sending ? null : () => _send(_input.text),
            ),
          ),
        ]),
      );
}
