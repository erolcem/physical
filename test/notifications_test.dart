// Proactive notifications: the pure reminder-computation (the platform scheduling
// is guarded to iOS/Android and verified on-device).
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/notifications.dart';

void main() {
  test('only timed habits produce reminders, at their time', () {
    const habits = [
      Habit(id: 'a', title: 'Lift', time: '07:30', createdAt: 'x'),
      Habit(id: 'b', title: 'Stretch', createdAt: 'x'), // untimed → skipped
      Habit(id: 'c', title: 'Sleep', time: '22:00', createdAt: 'x'),
    ];
    final r = habitReminders(habits);
    expect(r.length, 2);
    final lift = r.firstWhere((x) => x.title == 'Lift');
    expect(lift.hour, 7);
    expect(lift.minute, 30);
    expect(r.any((x) => x.title == 'Sleep' && x.hour == 22), true);
  });

  test('malformed time is ignored', () {
    const habits = [Habit(id: 'a', title: 'X', time: 'oops', createdAt: 'x')];
    expect(habitReminders(habits), isEmpty);
  });

  test('reminder ids are stable and non-negative per habit', () {
    const h = Habit(id: 'a', title: 'Lift', time: '07:30', createdAt: 'x');
    final r1 = habitReminders([h]).single;
    final r2 = habitReminders([h]).single;
    expect(r1.id, r2.id);
    expect(r1.id, greaterThanOrEqualTo(0));
  });

  test('a daily habit yields one daily reminder (no weekday)', () {
    const h = Habit(id: 'a', title: 'Water', time: '09:00', createdAt: 'x');
    final r = habitReminders([h]).single;
    expect(r.weekday, isNull);
  });

  test('a weekly habit fires ONLY on its due weekdays, not daily', () {
    // The bug: a Mon(1)/Thu(4) habit used to get a daily-repeating reminder.
    const h = Habit(id: 'a', title: 'Lift', time: '07:30',
        cadence: 'weekly', days: [1, 4], createdAt: 'x');
    final r = habitReminders([h]);
    expect(r.length, 2);
    expect(r.map((x) => x.weekday).toSet(), {1, 4});
    expect(r.every((x) => x.hour == 7 && x.minute == 30), isTrue);
    // Distinct ids per weekday so neither overwrites the other on schedule.
    expect(r.map((x) => x.id).toSet().length, 2);
  });

  test('a weekly habit with no chosen days falls back to a single daily reminder', () {
    const h = Habit(id: 'a', title: 'X', time: '08:00', cadence: 'weekly', createdAt: 'x');
    final r = habitReminders([h]).single;
    expect(r.weekday, isNull);
  });
}
