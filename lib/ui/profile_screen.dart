// ui/profile_screen.dart — the Progress tab's Profile section. Identity stats
// are NUMERIC ENTRIES, not graphs: age (derived from DOB), height, weight and
// body fat each show their current number with one-tap manual entry. Everything
// still auto-syncs from Google Health where available — manual entry is the
// always-available path, sync just fills it in for you.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metrics.dart' show metricById, tierColor;
import '../data/profile.dart' show syncAgeFromDob;
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log;
import '../state/providers.dart';

const _bg = Color(0xFF04050C);
const _card = Color(0xFF101226);
const _accent = Color(0xFF5B6AF8);
const _teal = Color(0xFF4CE0C3);
const _muted = Color(0xFF7880A8);
const _border = Color(0x12FFFFFF);

void openProfileScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
}

/// Set the date of birth → the 'age' log derives itself (and re-derives on
/// birthdays). Shared by the Profile screen and the home body-stats strip.
Future<void> promptDob(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final existing = repo.loadDob();
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime.tryParse(existing ?? '') ?? DateTime(now.year - 25),
    firstDate: DateTime(now.year - 120),
    lastDate: now,
    helpText: 'Date of birth — age then updates itself',
  );
  if (picked == null) return;
  repo.saveDob(
      '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
  final age = syncAgeFromDob(repo);
  ref.read(logsProvider.notifier).reload();
  if (context.mounted && age != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Age set to $age — it now updates itself on birthdays.'),
        duration: const Duration(seconds: 2)));
  }
}

/// One-field numeric log for a simple metric (weight / height / body fat …).
/// Returns true when a value was saved. The manual path that always works —
/// Google Health sync fills the same metrics in automatically when connected.
Future<bool> promptQuickLog(BuildContext context, WidgetRef ref, String metricId,
    {String? helper}) async {
  final m = metricById(metricId);
  final latest = ref.read(latestLogsProvider)[metricId];
  final ctrl = TextEditingController(
      text: latest == null
          ? ''
          : (latest.value % 1 == 0
              ? latest.value.toStringAsFixed(0)
              : latest.value.toStringAsFixed(1)));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _card,
      title: Text('Log ${m.label}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: '${m.label} (${m.unit})'),
        ),
        if (helper != null) ...[
          const SizedBox(height: 8),
          Text(helper, style: const TextStyle(fontSize: 11.5, color: _muted)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true) return false;
  final v = double.tryParse(ctrl.text.trim());
  if (v == null || v <= 0) return false;
  ref.read(logsProvider.notifier)
      .add(metricId, Log(metricId, v, ts: DateTime.now().toIso8601String()));
  return true;
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestLogsProvider);
    final age = latest['age']?.value;
    final h = latest['height']?.value;
    final w = latest['bodyweight']?.value;
    final bf = latest['body_fat_pct'];
    final bfRank = bf != null ? eng.scoreLog(bf) : null;

    String num1(double? v, {int dp = 0}) => v == null ? '—' : v.toStringAsFixed(dp);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                    'Plain numbers, not graphs. Tap a row to enter a value by hand — '
                    'Google Health fills these in automatically when connected.',
                    style: TextStyle(fontSize: 12, color: _muted, height: 1.35)),
              ),
              _row(
                context,
                label: 'Age',
                value: age == null ? 'set date of birth' : '${num1(age)} yr',
                caption: 'Derived from your date of birth — updates itself on birthdays.',
                icon: Icons.cake_outlined,
                onTap: () => promptDob(context, ref),
              ),
              _row(
                context,
                label: 'Sex',
                value: 'Male',
                caption: 'The reference population every rank compares against (young men).',
                icon: Icons.person_outline,
              ),
              _row(
                context,
                label: 'Height',
                value: h == null ? 'tap to enter' : '${num1(h)} cm',
                caption: 'Used for the calorie-burn estimate. Syncs from Google Health too.',
                icon: Icons.height,
                onTap: () => promptQuickLog(context, ref, 'height'),
              ),
              _row(
                context,
                label: 'Weight',
                value: w == null ? 'tap to enter' : '${w.toStringAsFixed(1)} kg',
                caption: 'Scales every strength rank (snapshotted per lift) and anchors '
                    'the diet energy balance. Charted on the Diet page.',
                icon: Icons.monitor_weight_outlined,
                onTap: () => promptQuickLog(context, ref, 'bodyweight',
                    helper: 'New lifts are ranked against the weight you are when you lift — '
                        'keeping this current keeps strength ranks honest.'),
              ),
              _row(
                context,
                label: 'Body fat',
                value: bf == null ? 'tap to enter' : '${bf.value.toStringAsFixed(1)} %',
                caption: 'Ranked in Recovery (≤12% is the health target). '
                    'Smart scale / caliper / DEXA — syncs from Google Health too.',
                icon: Icons.percent,
                trailing: bfRank == null
                    ? null
                    : Text('${bfRank.tier} ${bfRank.sub}',
                        style: TextStyle(
                            color: tierColor(bfRank.tier), fontWeight: FontWeight.w800, fontSize: 13)),
                onTap: () => promptQuickLog(context, ref, 'body_fat_pct'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context,
      {required String label,
      required String value,
      required String caption,
      required IconData icon,
      Widget? trailing,
      VoidCallback? onTap}) {
    final editable = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12), shape: BoxShape.circle,
                  border: Border.all(color: _accent.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    if (trailing != null) trailing,
                  ]),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _teal)),
                  const SizedBox(height: 3),
                  Text(caption, style: const TextStyle(fontSize: 11, color: _muted, height: 1.3)),
                ]),
              ),
              if (editable)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.edit_outlined, size: 16, color: _muted),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
