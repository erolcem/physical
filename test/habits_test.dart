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
    test('survives encode/decode', () {
      const h = Habit(id: 'a', title: 'Train', linkedMetricId: 'bench', createdAt: '2026-06-24T00:00:00');
      final back = Habit.fromJson(h.toJson());
      expect(back.id, 'a');
      expect(back.title, 'Train');
      expect(back.linkedMetricId, 'bench');
      expect(back.createdAt, '2026-06-24T00:00:00');
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
