// state/habit_providers.dart — Riverpod wiring for the Habits layer. One notifier
// holds both the habit list and the per-day completion set so they stay in sync;
// it reads/writes through the same Repository seam as logs.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/habits.dart';
import '../data/repository.dart';
import 'providers.dart';

/// Immutable snapshot of the Habits layer.
class HabitsState {
  final List<Habit> habits;
  final Map<String, Set<String>> completions; // habitId → done date-keys
  const HabitsState(this.habits, this.completions);

  bool doneToday(String habitId) =>
      completions[habitId]?.contains(todayKey()) ?? false;

  Set<String> doneFor(String habitId) => completions[habitId] ?? const {};
}

final habitsProvider =
    StateNotifierProvider<HabitsNotifier, HabitsState>((ref) {
  return HabitsNotifier(ref.watch(repositoryProvider));
});

class HabitsNotifier extends StateNotifier<HabitsState> {
  final Repository repo;
  HabitsNotifier(this.repo)
      : super(HabitsState(repo.loadHabits(), repo.loadCompletions()));

  void addHabit(String title,
      {String section = 'misc',
      String? verify,
      String? linkedMetricId,
      double? target,
      String compare = 'gte',
      String? goalKey,
      String unit = '',
      List<String> products = const [],
      String? time,
      int durationMins = 0,
      String cadence = 'daily',
      List<int> days = const []}) {
    final t = title.trim();
    if (t.isEmpty) return;
    repo.saveHabit(Habit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: t,
      section: section,
      verify: verify ?? sectionOf(section).verify,
      linkedMetricId: linkedMetricId,
      target: target,
      compare: compare,
      goalKey: goalKey,
      unit: unit,
      products: products,
      time: time,
      durationMins: durationMins,
      cadence: cadence,
      days: days,
      createdAt: DateTime.now().toIso8601String(),
    ));
    _reload();
  }

  void removeHabit(String id) {
    repo.deleteHabit(id);
    _reload();
  }

  /// Toggle today's check-off for a habit.
  void toggleToday(String id) {
    repo.setCompletion(id, todayKey(), !state.doneToday(id));
    _reload();
  }

  void _reload() =>
      state = HabitsState(repo.loadHabits(), repo.loadCompletions());
}
