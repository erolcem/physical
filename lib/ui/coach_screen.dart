// ui/coach_screen.dart — the AI Coach tab (PDF Part 5). A chat with Physical's
// coach; the backend feeds Gemini the user's real ranks (its data) plus the live
// habits + profile this tab sends. Requires sign-in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart';
import '../data/diet.dart' show todayDiet;
import '../data/habits.dart' show currentStreak;
import '../data/metrics.dart' show metricById, metrics, MetricTier;
import '../data/sync.dart' show apiClientProvider;
import '../data/workout.dart' show exercisesOverDays, sessionsOverDays, volumeOverDays;
import '../state/habit_providers.dart';
import '../state/log_providers.dart';
import '../state/profile_providers.dart';
import '../state/providers.dart' show latestLogsProvider;

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
const _teal = Color(0xFF4CE0C3);
const _muted = Color(0xFF7880A8);

const _suggestions = [
  'Review my training',
  'Review my sleep & recovery',
  'What should I improve?',
  'Plan my week',
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

class _CoachTabState extends ConsumerState<CoachTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _loading = true, _signedIn = false, _configured = false, _sending = false;

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
      if (mounted) {
        setState(() { _signedIn = true; _configured = st['configured'] == true; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _signedIn = true; _configured = false; _loading = false; });
    }
  }

  List<Map<String, dynamic>> _habitsCtx() {
    final hs = ref.read(habitsProvider);
    return [
      for (final h in hs.habits)
        {
          'title': h.title,
          'category': h.category,
          'done_today': hs.doneToday(h.id),
          'streak': currentStreak(hs.doneFor(h.id)),
        }
    ];
  }

  Map<String, dynamic> _profileCtx() {
    final p = ref.read(profileProvider);
    return {
      if (p.age != null) 'age': p.age,
      'gender': p.gender,
      if (p.heightCm != null) 'heightCm': p.heightCm,
      if (p.weightKg != null) 'weightKg': p.weightKg,
      if (p.bodyFatPct != null) 'bodyFatPct': p.bodyFatPct,
    };
  }

  Map<String, dynamic> _dietCtx() {
    final t = todayDiet(ref.read(dietProvider));
    return {
      'calories': t.calories, 'protein': t.protein,
      'carbs': t.carbs, 'fat': t.fat, 'items': t.items,
    };
  }

  Map<String, dynamic> _trainingCtx() {
    final w = ref.read(workoutProvider);
    final ids = exercisesOverDays(w);
    return {
      'weekly_volume': volumeOverDays(w).round(),
      'sessions': sessionsOverDays(w),
      'exercises': [for (final id in ids) metricById(id).label],
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
          diet: _dietCtx(), training: _trainingCtx(), aesthetics: _aestheticsCtx());
      final reply = (res['reply'] as String?) ?? '';
      final actions =
          ((res['actions'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _messages.add(_Msg('model', reply, actions: actions)));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_Msg('model',
            e.status == 503
                ? "I'm not set up on the server yet — add a GEMINI_API_KEY and I'll be right here."
                : "Sorry, I couldn't respond just now. Try again in a moment.")));
      }
    } catch (_) {
      if (mounted) setState(() => _messages.add(_Msg('model', "Couldn't reach the coach.")));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _showContext() async {
    final api = ref.read(apiClientProvider);
    final habits = _habitsCtx();
    final profile = _profileCtx();
    final diet = _dietCtx();
    final training = _trainingCtx();
    final aesthetics = _aestheticsCtx();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => FutureBuilder<Map<String, dynamic>>(
        future: api.coachContext(
            habits: habits, profile: profile, diet: diet, training: training, aesthetics: aesthetics),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('What your coach sees',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (c['profile'] != null) row('Profile', c['profile'] as String),
          if (c['overall'] != null) row('Overall', c['overall'] as String),
          if (cats.isNotEmpty)
            row('Categories', cats.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
          if (c['weakest'] != null) row('Weakest', c['weakest'] as String),
          if (c['strongest'] != null) row('Strongest', c['strongest'] as String),
          if (recent.isNotEmpty)
            row('Recent', recent.entries.map((e) => '${e.key}: ${e.value}').join(', ')),
          if (c['diet'] != null) row('Diet', c['diet'] as String),
          if (c['training'] != null) row('Training', c['training'] as String),
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
          TextButton.icon(
            onPressed: _showContext,
            icon: const Icon(Icons.visibility_outlined, size: 15),
            label: const Text('What I see'),
            style: TextButton.styleFrom(foregroundColor: _muted, textStyle: const TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      Expanded(
        child: _messages.isEmpty
            ? _welcome()
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _messages.length) return _bubble(_Msg('model', '…'));
                  return _messageWidget(_messages[i]);
                },
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
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s),
                  backgroundColor: _card,
                  side: const BorderSide(color: _accent),
                  labelStyle: const TextStyle(color: _accent, fontSize: 12),
                  onPressed: () => _send(s),
                ),
            ],
          ),
        ],
      );

  Widget _messageWidget(_Msg m) {
    if (m.actions.isEmpty) return _bubble(m);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _bubble(m),
      for (final a in m.actions) _actionCard(a),
    ]);
  }

  Widget _actionCard(Map<String, dynamic> a) {
    final applied = a['_applied'] == true;
    final isAdd = a['type'] == 'add_habit';
    final title = a['title'] as String? ?? '';
    final desc = isAdd
        ? 'Add habit: $title'
            '${a['category'] != null ? ' · ${a['category']}' : ''}'
            '${a['durationMins'] != null ? ' · ${a['durationMins']}min' : ''}'
            '${a['time'] != null ? ' · ${a['time']}' : ''}'
        : 'Remove habit: $title';
    return Container(
      margin: const EdgeInsets.only(top: 6, right: 40, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(isAdd ? Icons.add_circle_outline : Icons.remove_circle_outline,
            color: _accent, size: 18),
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
          category: (a['category'] as String?) ?? 'other',
          time: a['time'] as String?,
          durationMins: (a['durationMins'] as num?)?.toInt() ?? 0);
    } else if (a['type'] == 'remove_habit') {
      final title = (a['title'] as String? ?? '').toLowerCase();
      final hs = ref.read(habitsProvider);
      final match = hs.habits.where((h) => h.title.toLowerCase() == title);
      if (match.isNotEmpty) notifier.removeHabit(match.first.id);
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
