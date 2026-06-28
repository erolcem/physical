import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/habits.dart';

void main() {
  Habit h({int dur = 0, double cost = 0, String cadence = 'daily', List<int> days = const [], String? time}) =>
      Habit(id: '$dur-$cost-$cadence-$time', title: 't', durationMins: dur, cost: cost,
          cadence: cadence, days: days, time: time, createdAt: '2026-06-28');

  test('occurrencesPerMonth: daily ≈30, weekly scales with days', () {
    expect(h().occurrencesPerMonth, 30);
    expect(h(cadence: 'weekly', days: [1, 3, 5]).occurrencesPerMonth, closeTo(3 * 30 / 7, 0.01));
  });

  test('monthly budget sums time + cost across recurrences', () {
    final b = monthlyBudget([
      h(dur: 30, cost: 0),                              // daily 30m → 900 min/mo
      h(dur: 0, cost: 2, cadence: 'weekly', days: [6]), // weekly £2 → ~£8.6/mo
    ]);
    expect(b.minutesPerMonth, 900);
    expect(b.costPerMonth, closeTo(2 * 30 / 7, 0.1));
  });

  test('hourDensity buckets habits by their hour', () {
    final d = hourDensity([h(time: '07:30'), h(time: '07:00'), h(time: '23:00'), h()]);
    expect(d[7], 2);
    expect(d[23], 1);
    expect(d.fold(0, (a, b) => a + b), 3); // untimed excluded
  });
}
