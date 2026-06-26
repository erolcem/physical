import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/readiness.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  group('dailyReadiness', () {
    test('null without any recovery data', () {
      expect(dailyReadiness(const {}, const []), isNull);
    });

    test('good recovery → high readiness (population branch)', () {
      final logs = {
        'hrv': [Log('hrv', 135)],
        'sleep_score': [Log('sleep_score', 95)],
        'resting_hr': [Log('resting_hr', 50)],
      };
      expect(dailyReadiness(logs, const [])!, greaterThan(85));
    });

    test('poor recovery → low readiness', () {
      final logs = {
        'hrv': [Log('hrv', 25)],
        'sleep_score': [Log('sleep_score', 55)],
        'resting_hr': [Log('resting_hr', 85)],
      };
      expect(dailyReadiness(logs, const [])!, lessThan(40));
    });

    test('personal baseline kicks in once ≥7 prior readings exist', () {
      // A stable ~50 HRV baseline, then today well above it → high goodness.
      final hist = [for (final v in <double>[48, 52, 49, 51, 50, 50, 50]) Log('hrv', v)];
      final logs = {'hrv': [...hist, Log('hrv', 70)]};
      expect(dailyReadiness(logs, const [])!, greaterThan(70));
      // Today well below the same baseline → low.
      final low = {'hrv': [...hist, Log('hrv', 32)]};
      expect(dailyReadiness(low, const [])!, lessThan(45));
    });

    test('readinessLabel buckets', () {
      expect(readinessLabel(90), 'Primed');
      expect(readinessLabel(70), 'Ready');
      expect(readinessLabel(30), 'Rest');
    });
  });
}
