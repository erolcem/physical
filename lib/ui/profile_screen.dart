// ui/profile_screen.dart — the Profile tab (PDF Part 1: age/gender/height/weight/
// body-fat) plus the quality-of-life "share your rank" slice of Part 6. Local-first.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metrics.dart' show tierColor;
import '../data/profile.dart';
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
