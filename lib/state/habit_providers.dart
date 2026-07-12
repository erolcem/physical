// state/habit_providers.dart — Riverpod wiring for the Habits layer. One notifier
// holds both the habit list and the per-day completion set so they stay in sync;
// it reads/writes through the same Repository seam as logs.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/habits.dart';
import '../data/notifications.dart';
import '../data/repository.dart';
import 'providers.dart';

/// Immutable snapshot of the Habits layer.
class HabitsState {
  final List<Habit> habits;
  final Map<String, Set<String>> completions; // habitId → done date-keys
  final Map<String, Map<String, bool>> aiVerdicts; // habitId → day → LLM verdict
  const HabitsState(this.habits, this.completions,
      [this.aiVerdicts = const {}]);

  bool doneToday(String habitId) =>
      completions[habitId]?.contains(todayKey()) ?? false;

  Set<String> doneFor(String habitId) => completions[habitId] ?? const {};

  /// The LLM verifier's judgement for a habit+day, or null when it hasn't run.
  bool? aiVerdictFor(String habitId, String day) => aiVerdicts[habitId]?[day];
}

final habitsProvider =
    StateNotifierProvider<HabitsNotifier, HabitsState>((ref) {
  return HabitsNotifier(ref.watch(repositoryProvider));
});

class HabitsNotifier extends StateNotifier<HabitsState> {
  final Repository repo;
  // Monotonic uniquifier: applying an AI plan adds habits in a tight loop, and
  // two microsecond timestamps CAN collide (the upsert would silently swallow
  // one habit).
  static int _seq = 0;
  HabitsNotifier(this.repo)
      : super(HabitsState(
            repo.loadHabits(), repo.loadCompletions(), repo.loadAiVerdicts()));

  void addHabit(String title,
      {String section = 'misc',
      String? verify,
      String? linkedMetricId,
      double? target,
      String compare = 'gte',
      String? goalKey,
      String unit = '',
      String description = '',
      List<String> products = const [],
      String? templateId,
      String? time,
      int durationMins = 0,
      double cost = 0,
      String cadence = 'daily',
      List<int> days = const []}) {
    final t = title.trim();
    if (t.isEmpty) return;
    repo.saveHabit(Habit(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      title: t,
      section: section,
      verify: verify ?? sectionOf(section).verify,
      linkedMetricId: linkedMetricId,
      target: target,
      compare: compare,
      goalKey: goalKey,
      unit: unit,
      description: description,
      products: products,
      templateId: templateId,
      time: time,
      durationMins: durationMins,
      cost: cost,
      cadence: cadence,
      days: days,
      createdAt: DateTime.now().toIso8601String(),
    ));
    _reload();
  }

  /// "Delete" ARCHIVES: the habit leaves the roster, but its identity,
  /// completions and AI verdicts stay — past days keep showing it, and the
  /// coach can reference it ("you used to…"). Removing an already-archived
  /// habit purges it for real (tombstoned so it can't ride back in on a merge).
  void removeHabit(String id) {
    final h = state.habits.where((x) => x.id == id).firstOrNull;
    if (h == null) return;
    if (h.archived) {
      repo.deleteHabit(id);
    } else {
      repo.saveHabit(h.archive());
    }
    _reload();
  }

  /// Update an existing habit in place (saveHabit upserts by id).
  void updateHabit(Habit habit) {
    repo.saveHabit(habit);
    _reload();
  }

  /// Retune an existing habit's quantitative target (the coach's adjust action).
  /// ACTIVE habits only: a same-titled archived habit must never be touched —
  /// matching it would rebuild it without archivedAt and silently resurrect it.
  void adjustTarget(String title, double target, {String? compare}) {
    final matches = activeHabits(state.habits)
        .where((h) => h.title.toLowerCase() == title.toLowerCase());
    if (matches.isEmpty) return;
    final o = matches.first;
    repo.saveHabit(Habit(
      id: o.id, title: o.title, section: o.section, verify: o.verify,
      linkedMetricId: o.linkedMetricId, target: target, compare: compare ?? o.compare,
      goalKey: o.goalKey, unit: o.unit, description: o.description, products: o.products,
      templateId: o.templateId, time: o.time,
      durationMins: o.durationMins, cost: o.cost, cadence: o.cadence, days: o.days,
      createdAt: o.createdAt,
    ));
    _reload();
  }

  /// Toggle today's check-off for a habit.
  void toggleToday(String id) {
    repo.setCompletion(id, todayKey(), !state.doneToday(id));
    _reload();
  }

  /// Toggle a habit's check-off for any [day] (the Habits tab can browse days).
  void toggleOn(String id, String day) {
    final done = state.completions[id]?.contains(day) ?? false;
    repo.setCompletion(id, day, !done);
    _reload();
  }

  /// Re-read from the repository (e.g. after AI verdicts were written by a sync).
  void reload() => _reload();

  void _reload() {
    state = HabitsState(
        repo.loadHabits(), repo.loadCompletions(), repo.loadAiVerdicts());
    // Keep the daily habit reminders in step with the ACTIVE roster (archived
    // habits are history — no reminders). No-op off iOS/Android.
    unawaited(
        NotificationService.instance.syncHabitReminders(activeHabits(state.habits)));
  }
}
