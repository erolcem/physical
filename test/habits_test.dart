// Habits (scaffolded model): sections/presets, cadence due-dates, two-step
// verification, streaks, weekly rollups, calendar recurrence, json round-trips.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

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
}
