// ui/grooming_checklist.dart — structured grooming self-rating → weighted 0–100.
// Grooming has no clinical/population norm, so this is an honest structured self-rating
// (not an instrument): rate each domain, get a weighted score to track over time.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _accent = Color(0xFF4CE0C3);
const _muted = Color(0xFF8A90B0);

// (domain, hint, weight). Weights sum to 1.
const List<(String, String, double)> groomingItems = [
  ('Haircut freshness', 'Recently cut & styled', 0.25),
  ('Facial hair', 'Trimmed / shaped to intent', 0.25),
  ('Body hair', 'Groomed to your preference', 0.20),
  ('Nails', 'Trimmed & clean', 0.15),
  ('Eyebrows', 'Tidy / shaped', 0.15),
];

/// Weighted grooming score (0–100) from per-domain 0–100 ratings.
double groomingScore(Map<String, double> ratings) {
  var sum = 0.0, w = 0.0;
  for (final (name, _, weight) in groomingItems) {
    sum += (ratings[name] ?? 0) * weight;
    w += weight;
  }
  return w == 0 ? 0 : sum / w;
}

Future<double?> measureGroomingFlow(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _GroomingSheet(),
  );
}

class _GroomingSheet extends ConsumerStatefulWidget {
  const _GroomingSheet();
  @override
  ConsumerState<_GroomingSheet> createState() => _GroomingSheetState();
}

class _GroomingSheetState extends ConsumerState<_GroomingSheet> {
  final Map<String, double> _r = {for (final it in groomingItems) it.$1: 70};

  @override
  Widget build(BuildContext context) {
    final score = groomingScore(_r);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 44, height: 5,
                decoration: BoxDecoration(color: const Color(0x21FFFFFF), borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Expanded(child: Text('Grooming check',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              Text(score.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _accent, height: 1)),
              const Padding(padding: EdgeInsets.only(bottom: 4, left: 2),
                  child: Text('/100', style: TextStyle(fontSize: 12, color: _muted))),
            ]),
            const SizedBox(height: 4),
            const Text('Rate each domain honestly — track the trend, not perfection.',
                style: TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 12),
            for (final (name, hint, weight) in groomingItems) _row(name, hint, weight),
            const SizedBox(height: 12),
            _btn('Save score', _accent, () => Navigator.of(context).pop(score)),
          ]),
        ),
      ),
    );
  }

  Widget _row(String name, String hint, double weight) {
    final v = _r[name]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          Text('${v.round()}', style: const TextStyle(color: _accent, fontWeight: FontWeight.w700)),
          Text('  · ${(weight * 100).round()}%', style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
        Text(hint, style: const TextStyle(color: _muted, fontSize: 11)),
        Slider(value: v, max: 100, divisions: 20, activeColor: _accent,
            onChanged: (x) => setState(() => _r[name] = x)),
      ]),
    );
  }

  Widget _btn(String label, Color c, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: Material(
          color: c,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(child: Text(label,
                  style: TextStyle(
                      color: c.computeLuminance() > 0.4 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 15))),
            ),
          ),
        ),
      );
}
