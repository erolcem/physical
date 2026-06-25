// Profile: json round-trip, BMI, and repository persistence round-trip.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/profile.dart';
import 'package:physical/data/repository.dart';

void main() {
  group('ProfileData', () {
    test('json round-trip preserves all fields', () {
      const p = ProfileData(
          age: 28, gender: 'male', heightCm: 180, weightKg: 78, bodyFatPct: 14);
      final back = ProfileData.fromJson(p.toJson());
      expect(back.age, 28);
      expect(back.gender, 'male');
      expect(back.heightCm, 180);
      expect(back.weightKg, 78);
      expect(back.bodyFatPct, 14);
    });

    test('empty/partial json defaults gender and leaves nulls', () {
      final p = ProfileData.fromJson({});
      expect(p.gender, 'male');
      expect(p.age, isNull);
      expect(p.bmi, isNull); // no height/weight
    });

    test('bmi computes from height + weight', () {
      const p = ProfileData(heightCm: 200, weightKg: 80);
      expect(p.bmi, closeTo(20.0, 1e-9)); // 80 / (2.0^2)
    });

    test('copyWith overrides only the given fields', () {
      const p = ProfileData(age: 20, gender: 'male');
      final q = p.copyWith(age: 21);
      expect(q.age, 21);
      expect(q.gender, 'male');
    });
  });

  group('Repository profile', () {
    test('save then load returns the same profile', () {
      final r = InMemoryRepository();
      expect(r.loadProfile().age, isNull); // default empty
      r.saveProfile(const ProfileData(age: 30, weightKg: 75));
      expect(r.loadProfile().age, 30);
      expect(r.loadProfile().weightKg, 75);
    });

    test('clear resets the profile', () {
      final r = InMemoryRepository();
      r.saveProfile(const ProfileData(age: 30));
      r.clear();
      expect(r.loadProfile().age, isNull);
    });
  });
}
