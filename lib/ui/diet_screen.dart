// ui/diet_screen.dart — food logging (PDF Part 1: name + macros → daily energy +
// protein, which feed the coach). Today's totals + add/remove food entries.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/diet.dart';
import '../data/habits.dart' show todayKey;
import '../state/log_providers.dart';

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _gold = Color(0xFFF6CF3E);
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
        const SizedBox(height: 16),
        const Text('TODAY', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
        const SizedBox(height: 6),
        if (today.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No food logged today.', style: TextStyle(color: _muted))),
          )
        else
          for (final e in today.reversed) _entryRow(ref, e),
      ]),
    );
  }

  Widget _totals(DietTotals t) => Card(
        color: _card,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("TODAY'S TOTAL",
                style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const SizedBox(height: 8),
            Text('${t.calories.round()} kcal',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _gold)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _macro('Protein', t.protein),
              _macro('Carbs', t.carbs),
              _macro('Fat', t.fat),
              _macro('Items', t.items.toDouble(), unit: ''),
            ]),
          ]),
        ),
      );

  Widget _macro(String label, double v, {String unit = 'g'}) => Column(children: [
        Text('${v.round()}$unit', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
      ]);

  Widget _entryRow(WidgetRef ref, FoodEntry e) => Card(
        color: _card,
        child: ListTile(
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${e.calories.round()} kcal · ${e.protein.round()}P / ${e.carbs.round()}C / ${e.fat.round()}F',
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
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Log food'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. Chicken & rice', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            num(kcal, 'kcal'),
            const SizedBox(height: 10),
            Row(children: [num(p, 'Protein'), num(c, 'Carbs'), num(f, 'Fat')]),
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
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
