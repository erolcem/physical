// ui/coach_screen.dart — the AI Coach tab (PDF Part 5). A chat with Physical's
// coach; the backend feeds Gemini the user's real ranks (its data) plus the live
// habits + profile this tab sends. Requires sign-in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart';
import '../data/habits.dart' show currentStreak;
import '../data/sync.dart' show apiClientProvider;
import '../state/habit_providers.dart';
import '../state/profile_providers.dart';

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
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
  const _Msg(this.role, this.text);
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
      final reply = await api.coachChat(
          message: text, history: history, habits: _habitsCtx(), profile: _profileCtx());
      if (mounted) setState(() => _messages.add(_Msg('model', reply)));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_Msg('model',
            e.status == 503
                ? "I'm not set up on the server yet — add a GEMINI_API_KEY and I'll be right here."
                : "Sorry, I couldn't respond just now. Try again in a moment.")));
      }
    } catch (_) {
      if (mounted) setState(() => _messages.add(const _Msg('model', "Couldn't reach the coach.")));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
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
      Expanded(
        child: _messages.isEmpty
            ? _welcome()
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _messages.length) return _bubble(const _Msg('model', '…'));
                  return _bubble(_messages[i]);
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
