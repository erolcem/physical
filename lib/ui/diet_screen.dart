// ui/diet_screen.dart — a holistic diet page (PDF Part 1/Part 2 per-domain layout):
// today's energy + a macro breakdown bar (protein/carbs/fat by kcal) + fibre, a
// 7-day calorie trend, and the day's food entries. Feeds the coach.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart';
import '../data/diet.dart';
import '../data/habits.dart' show todayKey;
import '../data/sync.dart' show apiClientProvider;
import '../state/log_providers.dart';

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _gold = Color(0xFFF6CF3E);
const _teal = Color(0xFF4CE0C3);
const _accent = Color(0xFF5B6AF8);
const _pink = Color(0xFFF85B88);
const _muted = Color(0xFF7880A8);

void openDietScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DietScreen()));
}

class DietScreen extends ConsumerWidget {
  const DietScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(dietProvider);
    final today = entriesFor(entries, todayKey());
    final t = todayDiet(entries);
    final trend = caloriesLastNDays(entries);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Diet')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _gold,
        foregroundColor: Colors.black,
        onPressed: () => _addDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Log food'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        _totals(t),
        const SizedBox(height: 12),
        _trend(trend),
        const SizedBox(height: 16),
        const Text('TODAY', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
        const SizedBox(height: 6),
        if (today.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No food logged today.', style: TextStyle(color: _muted))))
        else
          for (final e in today.reversed) _entryRow(ref, e),
      ]),
    );
  }

  Widget _totals(DietTotals t) {
    final macroKcal = t.proteinKcal + t.carbsKcal + t.fatKcal;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("TODAY'S TOTAL", style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 8),
          Text('${t.calories.round()} kcal',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _gold)),
          const SizedBox(height: 12),
          // Macro split of energy (protein/carbs/fat by kcal).
          if (macroKcal > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Row(children: [
                Expanded(flex: (t.proteinKcal * 100).round().clamp(0, 1 << 30),
                    child: Container(height: 10, color: _teal)),
                Expanded(flex: (t.carbsKcal * 100).round().clamp(0, 1 << 30),
                    child: Container(height: 10, color: _accent)),
                Expanded(flex: (t.fatKcal * 100).round().clamp(0, 1 << 30),
                    child: Container(height: 10, color: _pink)),
              ]),
            ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _macro('Protein', t.protein, _teal),
            _macro('Carbs', t.carbs, _accent),
            _macro('Fat', t.fat, _pink),
            _macro('Fibre', t.fibre, _gold),
          ]),
          if (t.micros.values.any((v) => v > 0)) ...[
            const SizedBox(height: 16),
            const Text('MICRONUTRIENTS', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in microLabels.keys)
                if ((t.micros[k] ?? 0) > 0) _microChip(k, t.micros[k]!),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _microChip(String key, double v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent.withValues(alpha: 0.3)),
        ),
        child: Text('${microLabels[key]} ${v.round()}${microUnit(key)}',
            style: const TextStyle(fontSize: 11, color: _accent, fontWeight: FontWeight.w600)),
      );

  Widget _macro(String label, double g, Color c) => Column(children: [
        Text('${g.round()}g', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
      ]);

  Widget _trend(List<double> kcal) {
    final maxK = kcal.fold<double>(1, (m, v) => v > m ? v : m);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LAST 7 DAYS · CALORIES',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < kcal.length; i++)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(kcal[i] > 0 ? '${(kcal[i] / 100).round() * 100}' : '',
                      style: const TextStyle(fontSize: 8, color: _muted)),
                  const SizedBox(height: 2),
                  Container(
                    width: 22,
                    height: 4 + 46 * (kcal[i] / maxK),
                    decoration: BoxDecoration(
                        color: i == kcal.length - 1 ? _gold : _gold.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ]),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _entryRow(WidgetRef ref, FoodEntry e) => Card(
        color: _card,
        child: ListTile(
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${e.calories.round()} kcal · ${e.protein.round()}P / ${e.carbs.round()}C / ${e.fat.round()}F'
              '${e.fibre > 0 ? ' / ${e.fibre.round()}fib' : ''}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18, color: _muted),
            onPressed: () => ref.read(dietProvider.notifier).remove(e.id),
          ),
        ),
      );

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final kcal = TextEditingController();
    final p = TextEditingController();
    final c = TextEditingController();
    final f = TextEditingController();
    final fib = TextEditingController();
    var micros = <String, double>{};
    var busy = false;

    Widget num(TextEditingController ctrl, String label) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            ),
          ),
        );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Estimate macros + micros from the typed description via Gemini.
          Future<void> autofill() async {
            final desc = name.text.trim();
            if (desc.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Type a food first, e.g. "2 eggs and toast"')));
              return;
            }
            setLocal(() => busy = true);
            try {
              final api = ref.read(apiClientProvider);
              await api.loadPersistedToken(); // ensure the auth header is set
              final n = await api.inferNutrition(desc);
              kcal.text = n.calories.round().toString();
              p.text = n.protein.round().toString();
              c.text = n.carbs.round().toString();
              f.text = n.fat.round().toString();
              fib.text = n.fibre.round().toString();
              micros = n.micros;
              setLocal(() => busy = false);
            } catch (e) {
              setLocal(() => busy = false);
              final msg = switch (e) {
                ApiException(status: 503) => 'Auto-fill needs the AI key set up — enter values manually.',
                ApiException(status: 401) => 'Sign in with Google (☁) to use AI auto-fill.',
                _ => "Couldn't estimate that — enter values manually.",
              };
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
              }
            }
          }

          return AlertDialog(
            backgroundColor: _card,
            title: const Text('Log food'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: name, autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => autofill(),
                  decoration: const InputDecoration(
                      hintText: 'e.g. Chicken & rice', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : autofill,
                    icon: busy
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(busy ? 'Estimating…' : 'Auto-fill nutrition with AI'),
                    style: OutlinedButton.styleFrom(foregroundColor: _teal),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [num(kcal, 'kcal'), num(fib, 'Fibre')]),
                const SizedBox(height: 10),
                Row(children: [num(p, 'Protein'), num(c, 'Carbs'), num(f, 'Fat')]),
                if (micros.values.any((v) => v > 0)) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Micros: ${[
                        for (final k in microLabels.keys)
                          if ((micros[k] ?? 0) > 0)
                            '${microLabels[k]} ${micros[k]!.round()}${microUnit(k)}'
                      ].join(' · ')}',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  ref.read(dietProvider.notifier).add(
                        name: name.text,
                        calories: double.tryParse(kcal.text) ?? 0,
                        protein: double.tryParse(p.text) ?? 0,
                        carbs: double.tryParse(c.text) ?? 0,
                        fat: double.tryParse(f.text) ?? 0,
                        fibre: double.tryParse(fib.text) ?? 0,
                        micros: micros,
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
}
