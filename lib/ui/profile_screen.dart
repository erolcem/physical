// ui/profile_screen.dart — the Profile tab (PDF Part 1: age/gender/height/weight/
// body-fat) plus the quality-of-life "share your rank" slice of Part 6. Local-first.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart';
import '../data/metrics.dart' show tierColor;
import '../data/profile.dart';
import '../data/sync.dart' show apiClientProvider;
import '../engine/rank_engine.dart' as eng;
import '../state/profile_providers.dart';
import '../state/providers.dart';
import 'badge.dart';

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
const _muted = Color(0xFF7880A8);

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});
  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _bodyFat;
  late String _gender;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _age = TextEditingController(text: p.age?.toString() ?? '');
    _height = TextEditingController(text: p.heightCm?.toString() ?? '');
    _weight = TextEditingController(text: p.weightKg?.toString() ?? '');
    _bodyFat = TextEditingController(text: p.bodyFatPct?.toString() ?? '');
    _gender = p.gender;
  }

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(profileProvider.notifier).save(ProfileData(
          age: int.tryParse(_age.text),
          gender: _gender,
          heightCm: double.tryParse(_height.text),
          weightKg: double.tryParse(_weight.text),
          bodyFatPct: double.tryParse(_bodyFat.text),
        ));
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved'), duration: Duration(seconds: 1)));
  }

  void _shareRank() {
    final overall = ref.read(overallProvider);
    final cats = ref.read(categoryRanksProvider);
    String cat(String id, String label) {
      final r = cats[id];
      return r == null ? '' : '\n$label: ${r.tier} ${r.sub}';
    }

    final text = '💪 Physical — my rank\n'
        '${overall.tier} ${overall.sub} · top ${overall.topPct.toStringAsFixed(1)}% of young men'
        '${cat('strength', 'Strength')}${cat('performance', 'Performance')}${cat('recovery', 'Recovery')}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rank copied — share it anywhere'),
        duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final overall = ref.watch(overallProvider);
    final profile = ref.watch(profileProvider);
    return Container(
      color: _bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _rankHeader(overall),
          const SizedBox(height: 12),
          _detailsCard(profile),
          const SizedBox(height: 12),
          const _FriendsSection(),
        ],
      ),
    );
  }

  Widget _rankHeader(eng.RankResult overall) {
    final c = tierColor(overall.tier);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          RankBadge(tier: overall.tier, sub: overall.sub, size: 84),
          const SizedBox(height: 10),
          Text('${overall.tier} ${overall.sub}',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
          const SizedBox(height: 2),
          Text('Top ${overall.topPct.toStringAsFixed(1)}% of young men',
              style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _shareRank,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Share my rank'),
            style: OutlinedButton.styleFrom(
                foregroundColor: _accent, side: const BorderSide(color: _accent)),
          ),
        ]),
      ),
    );
  }

  Widget _detailsCard(ProfileData profile) {
    final bmi = profile.bmi;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('DETAILS',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _numField(_age, 'Age', 'yrs')),
            const SizedBox(width: 10),
            Expanded(child: _genderField()),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _numField(_height, 'Height', 'cm')),
            const SizedBox(width: 10),
            Expanded(child: _numField(_weight, 'Weight', 'kg')),
          ]),
          const SizedBox(height: 12),
          _numField(_bodyFat, 'Body fat', '%'),
          if (bmi != null) ...[
            const SizedBox(height: 14),
            Text('BMI ${bmi.toStringAsFixed(1)}',
                style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _dirty ? _save : null,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Save'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, String suffix) =>
      TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() => _dirty = true),
        decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder()),
      );

  Widget _genderField() => DropdownButtonFormField<String>(
        initialValue: _gender,
        dropdownColor: _card,
        decoration:
            const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'male', child: Text('Male')),
          DropdownMenuItem(value: 'female', child: Text('Female')),
          DropdownMenuItem(value: 'other', child: Text('Other')),
        ],
        onChanged: (v) => setState(() {
          _gender = v ?? 'male';
          _dirty = true;
        }),
      );
}

// ── Friends (PDF Part 6): add by email, accept requests, compare overall ranks ──
class _FriendsSection extends ConsumerStatefulWidget {
  const _FriendsSection();
  @override
  ConsumerState<_FriendsSection> createState() => _FriendsSectionState();
}

class _FriendsSectionState extends ConsumerState<_FriendsSection> {
  bool _loading = true, _signedIn = false, _busy = false;
  List<Map<String, dynamic>> _friends = [], _pending = [];
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    try {
      await api.loadPersistedToken();
      if (!api.isSignedIn) {
        if (mounted) setState(() { _signedIn = false; _loading = false; });
        return;
      }
      final f = await api.listFriends();
      final p = await api.pendingFriendRequests();
      // Leaderboard: highest rank first; the unranked sink to the bottom.
      f.sort((a, b) => _rankVal(b).compareTo(_rankVal(a)));
      if (mounted) {
        setState(() { _signedIn = true; _friends = f; _pending = p; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _msg = "Couldn't load friends."; });
    }
  }

  double _rankVal(Map<String, dynamic> friend) =>
      ((friend['rank']?['rank_value']) as num?)?.toDouble() ?? -1;

  Future<void> _add() async {
    final email = await _askEmail();
    if (email == null || email.trim().isEmpty) return;
    setState(() { _busy = true; _msg = null; });
    final api = ref.read(apiClientProvider);
    try {
      final r = await api.addFriend(email.trim());
      _msg = r['status'] == 'accepted' ? 'Already friends' : 'Request sent';
      await _load();
    } on ApiException catch (e) {
      _msg = e.status == 404
          ? 'No account with that email'
          : (e.status == 400 ? "You can't add yourself" : 'Request failed');
    } catch (_) {
      _msg = "Couldn't reach the backend.";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _msg = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askEmail() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Add friend'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              hintText: 'their account email', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Send request')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiClientProvider);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('FRIENDS',
                style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            if (_signedIn)
              TextButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
          else if (!_signedIn || !api.isSignedIn)
            const Text('Sign in via Cloud Sync (☁) to add friends and compare ranks.',
                style: TextStyle(color: _muted, fontSize: 13))
          else ...[
            for (final p in _pending) _pendingRow(p),
            if (_friends.isEmpty && _pending.isEmpty)
              const Text('No friends yet — add one by their account email.',
                  style: TextStyle(color: _muted, fontSize: 13)),
            for (final f in _friends) _friendRow(f),
          ],
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_msg!,
                  style: const TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }

  Widget _pendingRow(Map<String, dynamic> p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Icon(Icons.mail_outline, color: _muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${p['email'] ?? p['requester_id']} wants to connect',
                style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _act(() =>
                    ref.read(apiClientProvider).acceptFriend(p['requester_id'] as String)),
            child: const Text('Accept'),
          ),
        ]),
      );

  Widget _friendRow(Map<String, dynamic> f) {
    final rank = f['rank'] as Map<String, dynamic>?;
    final name = (f['email'] ?? f['user_id']) as String;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        if (rank != null)
          RankBadge(tier: rank['tier'] as String, sub: rank['sub'] as String, size: 34)
        else
          const SizedBox(
              width: 34, height: 34,
              child: Icon(Icons.help_outline, color: _muted, size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                overflow: TextOverflow.ellipsis),
            Text(
                rank == null
                    ? 'No data yet'
                    : '${rank['tier']} ${rank['sub']} · top ${(rank['top_pct'] as num).toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 12,
                    color: rank == null ? _muted : tierColor(rank['tier'] as String))),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: _muted),
          onPressed: _busy
              ? null
              : () => _act(() =>
                  ref.read(apiClientProvider).removeFriend(f['user_id'] as String)),
        ),
      ]),
    );
  }
}
