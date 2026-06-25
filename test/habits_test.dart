// Habits foundation: streak math, two-step verification rule, and repository
// round-trips. Pure logic with fixed dates so it can't flake.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/repository.dart';

void main() {
  group('dateKey', () {
    test('zero-pads to YYYY-MM-DD', () {
      expect(dateKey(DateTime(2026, 6, 4)), '2026-06-04');
      expect(dateKey(DateTime(2026, 12, 24)), '2026-12-24');
    });
  });

  group('currentStreak', () {
    final today = DateTime(2026, 6, 24);
    String k(int dayOffset) => dateKey(today.subtract(Duration(days: dayOffset)));

    test('no completions → 0', () {
      expect(currentStreak({}, today: today), 0);
    });

    test('today + prior consecutive days count', () {
      expect(currentStreak({k(0), k(1), k(2)}, today: today), 3);
    });

    test('today unticked still counts a run ending yesterday', () {
      expect(currentStreak({k(1), k(2)}, today: today), 2);
    });

    test('a gap breaks the streak', () {
      expect(currentStreak({k(0), k(2), k(3)}, today: today), 1); // gap on day-1
    });
  });

  group('statusFor (two-step verification)', () {
    const linked = Habit(id: '1', title: 'Sleep', linkedMetricId: 'sleep_score', createdAt: 'x');
    const manual = Habit(id: '2', title: 'Stretch', createdAt: 'x');

    test('untouched → notDone', () {
      expect(statusFor(linked, doneToday: false, hasLinkedLogToday: true), HabitStatus.notDone);
    });
    test('ticked but no corroborating log → manual', () {
      expect(statusFor(linked, doneToday: true, hasLinkedLogToday: false), HabitStatus.manual);
    });
    test('ticked + same-day linked log → verified', () {
      expect(statusFor(linked, doneToday: true, hasLinkedLogToday: true), HabitStatus.verified);
    });
    test('no linked metric is always manual when ticked', () {
      expect(statusFor(manual, doneToday: true, hasLinkedLogToday: true), HabitStatus.manual);
    });
  });

  group('Habit json round-trip', () {
    test('survives encode/decode with planner fields', () {
      const h = Habit(
          id: 'a',
          title: 'Train',
          category: 'strength',
          time: '07:30',
          durationMins: 60,
          costPerMonth: 40,
          linkedMetricId: 'bench',
          createdAt: '2026-06-24T00:00:00');
      final back = Habit.fromJson(h.toJson());
      expect(back.category, 'strength');
      expect(back.time, '07:30');
      expect(back.durationMins, 60);
      expect(back.costPerMonth, 40);
      expect(back.linkedMetricId, 'bench');
    });

    test('tolerates legacy json without planner fields (defaults)', () {
      final back = Habit.fromJson(
          {'id': 'x', 'title': 'Old', 'metric': null, 'created': 't'});
      expect(back.category, 'other');
      expect(back.time, isNull);
      expect(back.durationMins, 0);
      expect(back.costPerMonth, 0);
    });
  });

  group('planner rollup + density', () {
    test('planFor sums per-day, per-month, and cost', () {
      const habits = [
        Habit(id: '1', title: 'Lift', durationMins: 60, costPerMonth: 30, createdAt: 'x'),
        Habit(id: '2', title: 'Walk', durationMins: 30, createdAt: 'x'),
      ];
      final p = planFor(habits);
      expect(p.minutesPerDay, 90);
      expect(p.minutesPerMonth, 2700); // 90 × 30
      expect(p.costPerMonth, 30);
      expect(p.pctOfMonth, closeTo(2700 / 43200 * 100, 1e-9));
    });

    test('densitySlots fills the right half-hour slots by category', () {
      const habits = [
        Habit(id: '1', title: 'AM lift', category: 'strength', time: '07:00', durationMins: 60, createdAt: 'x'),
      ];
      final slots = densitySlots(habits);
      expect(slots.length, 48);
      // 07:00 = slot 14; 60 min spans slots 14 and 15.
      expect(slots[14].categoryId, 'strength');
      expect(slots[15].categoryId, 'strength');
      expect(slots[13].categoryId, isNull);
      expect(slots[16].categoryId, isNull);
    });

    test('untimed or zero-duration habits do not occupy the day', () {
      const habits = [Habit(id: '1', title: 'x', durationMins: 0, createdAt: 'x')];
      expect(densitySlots(habits).every((s) => s.categoryId == null), true);
    });
  });

  group('weekly history', () {
    final today = DateTime(2026, 6, 24);

    test('lastNDays returns n keys, oldest first, ending today', () {
      final days = lastNDays(7, today: today);
      expect(days.length, 7);
      expect(days.first, '2026-06-18');
      expect(days.last, '2026-06-24');
    });

    test('dailyDoneCounts tallies completions per day across habits', () {
      const habits = [
        Habit(id: '1', title: 'a', createdAt: 'x'),
        Habit(id: '2', title: 'b', createdAt: 'x'),
      ];
      final completions = {
        '1': {'2026-06-24', '2026-06-23'},
        '2': {'2026-06-24'},
      };
      // days 18..24 → both ticked only today, h1 also yesterday.
      expect(dailyDoneCounts(habits, completions, today: today),
          [0, 0, 0, 0, 0, 1, 2]);
    });
  });

  group('Repository habits', () {
    test('save / load / update by id (no dupes)', () {
      final r = InMemoryRepository();
      r.saveHabit(const Habit(id: '1', title: 'Train', createdAt: 'x'));
      r.saveHabit(const Habit(id: '1', title: 'Train hard', createdAt: 'x')); // same id → update
      r.saveHabit(const Habit(id: '2', title: 'Sleep', createdAt: 'x'));
      final habits = r.loadHabits();
      expect(habits.length, 2);
      expect(habits.firstWhere((h) => h.id == '1').title, 'Train hard');
    });

    test('completions toggle on/off and isolate per habit', () {
      final r = InMemoryRepository();
      r.setCompletion('1', '2026-06-24', true);
      r.setCompletion('1', '2026-06-23', true);
      r.setCompletion('2', '2026-06-24', true);
      expect(r.loadCompletions()['1'], {'2026-06-24', '2026-06-23'});
      r.setCompletion('1', '2026-06-24', false);
      expect(r.loadCompletions()['1'], {'2026-06-23'});
    });

    test('deleteHabit drops its completions too', () {
      final r = InMemoryRepository();
      r.saveHabit(const Habit(id: '1', title: 'Train', createdAt: 'x'));
      r.setCompletion('1', '2026-06-24', true);
      r.deleteHabit('1');
      expect(r.loadHabits(), isEmpty);
      expect(r.loadCompletions().containsKey('1'), false);
    });

    test('clear wipes habits and completions', () {
      final r = InMemoryRepository();
      r.saveHabit(const Habit(id: '1', title: 'Train', createdAt: 'x'));
      r.setCompletion('1', '2026-06-24', true);
      r.clear();
      expect(r.loadHabits(), isEmpty);
      expect(r.loadCompletions(), isEmpty);
    });
  });
}
