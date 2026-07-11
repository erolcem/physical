// Habits (scaffolded model): sections/presets, cadence due-dates, two-step
// verification, streaks, weekly rollups, calendar recurrence, json round-trips.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/habit_providers.dart' show HabitsNotifier;

void main() {
  group('sections & presets', () {
    test('every preset belongs to a real section', () {
      for (final p in habitPresets) {
        expect(habitSections.containsKey(p.section), true, reason: p.title);
      }
    });
    test('presetsFor returns only that section; sectionOf falls back to misc', () {
      expect(presetsFor('sleep').every((p) => p.section == 'sleep'), true);
      expect(presetsFor('sleep'), isNotEmpty);
      expect(sectionOf('nonsense').id, 'misc');
    });
    test('a sleep preset verifies by a metric, an exercise preset by a workout', () {
      expect(presetsFor('sleep').first.verify, 'metric');
      expect(presetsFor('exercise').first.verify, 'workout');
    });
  });

  group('cadence', () {
    test('daily habits are always due; weekly only on chosen weekdays', () {
      const daily = Habit(id: 'd', title: 'x', cadence: 'daily', createdAt: 'x');
      final date = DateTime(2026, 6, 22);
      expect(isDueOn(daily, date), true);
      final wd = date.weekday;
      final weekly = Habit(id: 'w', title: 'x', cadence: 'weekly', days: [wd], createdAt: 'x');
      expect(isDueOn(weekly, date), true);
      expect(isDueOn(weekly, date.add(const Duration(days: 1))), false);
    });
  });

  group('two-step verification', () {
    const linked = Habit(id: '1', title: 'Sleep', section: 'sleep', verify: 'metric', linkedMetricId: 'sleep_score', createdAt: 'x');
    const manual = Habit(id: '2', title: 'Skincare', section: 'aesthetics', verify: 'manual', createdAt: 'x');
    test('untouched → notDone', () => expect(statusFor(linked, doneToday: false, corroborated: true), HabitStatus.notDone));
    test('ticked, not corroborated → manual', () => expect(statusFor(linked, doneToday: true, corroborated: false), HabitStatus.manual));
    test('ticked + corroborated → verified', () => expect(statusFor(linked, doneToday: true, corroborated: true), HabitStatus.verified));
    test('manual habit is never auto-verified', () => expect(statusFor(manual, doneToday: true, corroborated: true), HabitStatus.manual));
  });

  group('corroboration from real/auto-collected data', () {
    test('metric verify is satisfied by a same-day log (e.g. an auto-synced sleep_score)', () {
      const h = Habit(id: '1', title: 'Sleep 8h', section: 'sleep', verify: 'metric', linkedMetricId: 'sleep_score', createdAt: 'x');
      final logs = {'sleep_score': [Log('sleep_score', 82, ts: '2026-06-25T00:00:00')]}; // shape of a Google-synced sample
      expect(corroboratedOn(h, '2026-06-25', logs: logs, workoutDays: const {}, foodDays: const {}), true);
      expect(corroboratedOn(h, '2026-06-24', logs: logs, workoutDays: const {}, foodDays: const {}), false);
    });
    test('workout verify is satisfied by a session that day', () {
      const h = Habit(id: '2', title: 'Train', section: 'exercise', verify: 'workout', createdAt: 'x');
      expect(corroboratedOn(h, '2026-06-25', logs: const {}, workoutDays: {'2026-06-25'}, foodDays: const {}), true);
      expect(corroboratedOn(h, '2026-06-25', logs: const {}, workoutDays: const {}, foodDays: const {}), false);
    });
    test('diet verify is satisfied by a food log that day', () {
      const h = Habit(id: '3', title: 'Log meals', section: 'diet', verify: 'diet', createdAt: 'x');
      expect(corroboratedOn(h, '2026-06-25', logs: const {}, workoutDays: const {}, foodDays: {'2026-06-25'}), true);
    });
    test('manual verify is never auto-corroborated', () {
      const h = Habit(id: '4', title: 'Skincare', section: 'aesthetics', verify: 'manual', createdAt: 'x');
      expect(corroboratedOn(h, '2026-06-25', logs: const {}, workoutDays: const {}, foodDays: const {}), false);
    });
  });

  group('currentStreak', () {
    final today = DateTime(2026, 6, 24);
    String k(int o) => dateKey(today.subtract(Duration(days: o)));
    test('counts today + prior consecutive', () => expect(currentStreak({k(0), k(1), k(2)}, today: today), 3));
    test('unticked today still counts a run ending yesterday', () => expect(currentStreak({k(1), k(2)}, today: today), 2));
    test('a gap breaks it', () => expect(currentStreak({k(0), k(2), k(3)}, today: today), 1));
  });

  group('dueStreak (weekly habits count in due-day steps)', () {
    // 2026-06-24 is a Wednesday; the habit is due Mon(1) + Thu(4).
    const weekly = Habit(id: 'w', title: 'Lift', cadence: 'weekly', days: [1, 4], createdAt: 'x');
    final wed = DateTime(2026, 6, 24);
    test('non-due days are skipped, not treated as misses', () {
      // Mon 22nd + Thu 18th done → streak 2 (calendar-day counting froze this at 1).
      expect(dueStreak(weekly, {'2026-06-22', '2026-06-18'}, today: wed), 2);
    });
    test('an unchecked TODAY does not break the run', () {
      final mon = DateTime(2026, 6, 22); // due today, not ticked yet
      expect(dueStreak(weekly, {'2026-06-18', '2026-06-15'}, today: mon), 2);
    });
    test('a missed PAST due day does break it', () {
      // Mon 22nd done, Thu 18th missed, Mon 15th done → only 1.
      expect(dueStreak(weekly, {'2026-06-22', '2026-06-15'}, today: wed), 1);
    });
    test('daily habit matches currentStreak', () {
      const daily = Habit(id: 'd', title: 'Walk', createdAt: 'x');
      String k(int o) => dateKey(wed.subtract(Duration(days: o)));
      expect(dueStreak(daily, {k(0), k(1), k(2)}, today: wed),
          currentStreak({k(0), k(1), k(2)}, today: wed));
      expect(dueStreak(daily, {k(1), k(2)}, today: wed), 2); // today pending
    });
    test('horizon caps the walk', () {
      expect(dueStreak(weekly, {'2026-06-22', '2026-06-18'}, today: wed, horizon: 3), 1);
    });
    test('due days BEFORE the habit was created are not counted as misses', () {
      // Created Fri 19th; the Mon before (15th) never existed as a due day, so a
      // gap there must not break a streak that runs back to creation.
      const w2 = Habit(id: 'w2', title: 'Lift', cadence: 'weekly', days: [1, 4],
          createdAt: '2026-06-19T09:00:00');
      // Due days on/after creation: Mon 22 + Thu 18? 18<19 so only Mon 22 counts.
      expect(dueStreak(w2, {'2026-06-22'}, today: wed), 1);
      // The pre-creation Mon 15 being undone doesn't matter — walk stops at creation.
      expect(dueStreak(w2, {'2026-06-22', '2026-06-15'}, today: wed), 1);
    });
  });

  group('isDueAndActive', () {
    const h = Habit(id: 'a', title: 'x', cadence: 'weekly', days: [1, 4],
        createdAt: '2026-06-19T09:00:00');
    test('due + on/after creation → active', () {
      expect(isDueAndActive(h, DateTime(2026, 6, 22)), isTrue); // Mon after creation
    });
    test('due but BEFORE creation → not active (no false "missed")', () {
      expect(isDueAndActive(h, DateTime(2026, 6, 15)), isFalse); // Mon before creation
    });
    test('not a due weekday → not active', () {
      expect(isDueAndActive(h, DateTime(2026, 6, 23)), isFalse); // Tue
    });
  });

  group('weekly history', () {
    final today = DateTime(2026, 6, 24);
    test('lastNDays: n keys, oldest first, ending today', () {
      final d = lastNDays(7, today: today);
      expect(d.length, 7);
      expect(d.first, '2026-06-18');
      expect(d.last, '2026-06-24');
    });
    test('dailyDoneCounts tallies per day across habits', () {
      const habits = [Habit(id: '1', title: 'a', createdAt: 'x'), Habit(id: '2', title: 'b', createdAt: 'x')];
      final completions = {'1': {'2026-06-24', '2026-06-23'}, '2': {'2026-06-24'}};
      expect(dailyDoneCounts(habits, completions, today: today), [0, 0, 0, 0, 0, 1, 2]);
    });
    test('valuesLastNDays: last value per day, null for gaps', () {
      final logs = [
        Log('sleep_score', 70, ts: '2026-06-22T08:00:00'),
        Log('sleep_score', 80, ts: '2026-06-24T07:00:00'),
        Log('sleep_score', 85, ts: '2026-06-24T09:00:00'), // later same day wins
      ];
      expect(valuesLastNDays(logs, n: 3, today: today), [70.0, null, 85.0]);
    });
  });

  group('calendar recurrence', () {
    test('untimed → null', () => expect(googleCalendarUrl(const Habit(id: '1', title: 'x', createdAt: 'x')), isNull));
    test('daily timed → FREQ=DAILY', () {
      final url = googleCalendarUrl(const Habit(id: '1', title: 'Lift', time: '07:00', createdAt: 'x'), now: DateTime(2026, 6, 24))!;
      expect(url, contains('FREQ%3DDAILY'));
      expect(url, contains('dates=20260624T070000%2F20260624T073000')); // default 30 min
    });
    test('weekly timed → FREQ=WEEKLY;BYDAY', () {
      final url = googleCalendarUrl(const Habit(id: '1', title: 'Lift', time: '07:00', cadence: 'weekly', days: [1, 3, 5], createdAt: 'x'), now: DateTime(2026, 6, 24))!;
      expect(url, contains('FREQ%3DWEEKLY'));
      expect(url, contains('BYDAY%3DMO%2CWE%2CFR'));
    });
  });

  group('Habit json', () {
    test('round-trips the scaffolded fields', () {
      const h = Habit(id: 'a', title: 'Train', section: 'exercise', verify: 'workout', time: '18:00', durationMins: 60, cadence: 'weekly', days: [1, 4], createdAt: 't');
      final b = Habit.fromJson(h.toJson());
      expect(b.section, 'exercise');
      expect(b.verify, 'workout');
      expect(b.cadence, 'weekly');
      expect(b.days, [1, 4]);
      expect(b.durationMins, 60);
    });
    test('legacy json (no verify/cadence/days) defaults from the section', () {
      final b = Habit.fromJson({'id': 'x', 'title': 'Old', 'cat': 'sleep', 'created': 't'});
      expect(b.section, 'sleep');
      expect(b.verify, 'metric'); // sleep section's default
      expect(b.cadence, 'daily');
      expect(b.days, isEmpty);
    });
  });

  group('Repository habits', () {
    test('save/update/delete + completions toggle', () {
      final r = InMemoryRepository();
      r.saveHabit(const Habit(id: '1', title: 'Train', section: 'exercise', createdAt: 'x'));
      r.saveHabit(const Habit(id: '1', title: 'Train hard', section: 'exercise', createdAt: 'x'));
      expect(r.loadHabits().length, 1);
      expect(r.loadHabits().first.title, 'Train hard');
      r.setCompletion('1', '2026-06-24', true);
      expect(r.loadCompletions()['1'], {'2026-06-24'});
      r.deleteHabit('1');
      expect(r.loadHabits(), isEmpty);
      expect(r.loadCompletions().containsKey('1'), false);
    });
  });

  group('inferPreset (free-typed titles adopt data verification)', () {
    test('a typed title naming a known quantity wires its exact verification', () {
      final sleep = inferPreset('sleep', 'Sleep score 80+');
      expect(sleep?.linkedMetricId, 'sleep_score');
      final hrv = inferPreset('recovery', 'morning HRV check');
      expect(hrv?.linkedMetricId, 'hrv');
      final steps = inferPreset('exercise', 'hit my steps');
      expect(steps?.linkedMetricId, 'steps');
      final protein = inferPreset('diet', 'Protein every day');
      expect(protein?.goalKey, 'protein');
      final chest = inferPreset('exercise', 'chest sets on push day');
      expect(chest?.goalKey, contains('chest'));
    });

    test('unrelated titles do NOT match — they stay AI-judged/tick-only', () {
      expect(inferPreset('diet', 'Dinner'), isNull);
      expect(inferPreset('exercise', 'Makiwara punching'), isNull);
      expect(inferPreset('misc', 'Call grandma'), isNull);
      expect(inferPreset('sleep', ''), isNull);
    });

    test('matching is scoped to the chosen section', () {
      // "protein" is a diet goal — typing it under exercise must not wire diet.
      expect(inferPreset('exercise', 'protein'), isNull);
    });
  });

  group('archive: deleting a habit retires it, history stays', () {
    Habit mk(String id, {String? created, String? archived}) => Habit(
        id: id, title: 'Meditate', section: 'recovery', verify: 'manual',
        createdAt: created ?? '2026-06-01T08:00:00', archivedAt: archived);

    test('remove = archive (completions + verdicts kept); second remove purges', () {
      final r = InMemoryRepository();
      final n = HabitsNotifier(r);
      n.addHabit('Meditate', section: 'recovery');
      final id = n.state.habits.single.id;
      n.toggleOn(id, '2026-07-01');
      r.setAiVerdict(id, '2026-07-02', true);
      // First delete: archived, NOT gone — history intact, no tombstone.
      n.removeHabit(id);
      final archived = n.state.habits.single;
      expect(archived.archived, isTrue);
      expect(n.state.completions[id], contains('2026-07-01'));
      expect(n.state.aiVerdicts[id]?['2026-07-02'], isTrue);
      expect(r.loadTombstones().any((t) => t.contains(id)), isFalse);
      // Second delete: purged for good, tombstoned against merges.
      n.removeHabit(id);
      expect(n.state.habits, isEmpty);
      expect(r.loadTombstones(), contains(entityKey('habit', id)));
    });

    test('isDueAndActive honours the active window: created ≤ day < archived', () {
      final h = mk('a', created: '2026-06-10T08:00:00', archived: '2026-07-01T09:00:00');
      expect(isDueAndActive(h, DateTime(2026, 6, 9)), isFalse); // before creation
      expect(isDueAndActive(h, DateTime(2026, 6, 15)), isTrue); // lived here
      expect(isDueAndActive(h, DateTime(2026, 7, 1)), isFalse); // archive day on
      expect(isDueAndActive(h, DateTime(2026, 7, 5)), isFalse); // after retirement
    });

    test('activeHabits/archivedHabits split; archived JSON round-trips', () {
      final habits = [mk('a'), mk('b', archived: '2026-07-01T09:00:00')];
      expect(activeHabits(habits).single.id, 'a');
      expect(archivedHabits(habits).single.id, 'b');
      final back = Habit.fromJson(habits[1].toJson());
      expect(back.archived, isTrue);
      expect(back.archivedAt, '2026-07-01T09:00:00');
    });

    test('merge adopts archival from another device (one-way; never resurrects)', () {
      final r = InMemoryRepository();
      r.saveHabit(mk('a')); // active here
      repoMerge(r, {
        'habits': [mk('a', archived: '2026-07-02T10:00:00').toJson()],
      });
      expect(r.loadHabits().single.archived, isTrue);
      // The reverse: an old snapshot with the ACTIVE version can't un-archive.
      repoMerge(r, {
        'habits': [mk('a').toJson()],
      });
      expect(r.loadHabits().single.archived, isTrue);
    });
  });
}
