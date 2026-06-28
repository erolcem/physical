// System verification — asserts the whole metric/exercise/weight/ranking stack
// is internally consistent. Guards against the kind of registry↔engine drift
// that let aesthetics get ranked. Pure logic (no widgets), runs fast.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:physical/data/metrics.dart';
import 'package:physical/data/body_figure_data.dart';
import 'package:physical/data/persistent_repository.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/state/providers.dart';
import 'package:physical/engine/rank_engine.dart' as eng;
import 'package:physical/engine/rank_engine.dart' show Log;

// A plausible probe value per non-strength ranked metric.
double _probe(String id) {
  switch (id) {
    case 'vo2max': return 48;
    case 'resting_hr': return 70;
    case 'hrv': return 50;
    case 'plank': return 80;
    case 'vert': return 43;
    case 'run5k_kmh': return 8.5;
    case 'deadhang': return 60;
    case 'hamstring_mobility': return 15;
    case 'body_fat_pct': return 20;
    default: return 50;
  }
}

void main() {
  group('Registry ↔ engine integrity', () {
    test('every ranked metric has a backing standard', () {
      for (final m in rankedMetrics) {
        expect(eng.standards.containsKey(m.id), isTrue,
            reason: 'ranked metric "${m.id}" has no standard — would render rankless or crash');
      }
    });

    test('unranked (tracked/background) metrics have NO standard', () {
      for (final m in metrics.where((m) => m.tier != MetricTier.ranked)) {
        expect(eng.standards.containsKey(m.id), isFalse,
            reason: 'unranked "${m.id}" must not have a standard (else it would feed the overall score)');
      }
    });

    test('all aesthetics are ranked (eye/voice real, rest provisional) + excluded from overall', () {
      // Every aesthetic now has a standard + tier. Eye (logMAR) and Voice (AVQI) use
      // real distributions; skin/oral/hair/grooming use ASSUMED provisional ones. All
      // stay in 'aesthetics' and are excluded from the overall score (overallProvider)
      // so appearance/sensory metrics never drag the headline rank.
      for (final id in ['eye', 'voice', 'skin', 'oral', 'hair', 'grooming']) {
        expect(metricById(id).tier, MetricTier.ranked, reason: '$id should be ranked');
        expect(eng.standards.containsKey(id), isTrue, reason: '$id should have a standard');
        expect(metricById(id).category, 'aesthetics');
      }
      // The assumed-distribution ones must be flagged provisional (drives the ⚠ in UI).
      for (final id in ['skin', 'oral', 'hair', 'grooming']) {
        expect(metricById(id).provisional, isTrue, reason: '$id rank must be flagged provisional');
      }
    });

    test('PDF categories: vo2max is performance, recovery = sleep/hrv/resting_hr', () {
      expect(metricById('vo2max').category, 'performance');
      for (final id in ['sleep_score', 'hrv', 'resting_hr']) {
        expect(metricById(id).category, 'recovery', reason: '$id should be recovery');
        expect(metricById(id).tier, MetricTier.ranked, reason: '$id should be ranked');
      }
    });

    test('sleep_score ranks from its standardised distribution', () {
      // Median ~77 ⇒ around the middle; 95 ⇒ top tier-ish; both must be valid.
      expect(eng.percentile('sleep_score', 95), greaterThan(eng.percentile('sleep_score', 60)));
      final res = eng.tierOf('sleep_score', 88);
      expect(eng.tiers.contains(res.tier), isTrue);
    });

    test('the 6 isolation lifts are flagged provisional', () {
      for (final id in ['lateral_raise', 'curl', 'skull_crusher', 'forearm_curl', 'calf_raise', 'crunch']) {
        expect(metricById(id).provisional, isTrue, reason: '$id should be flagged provisional');
      }
    });

    test('every body-graph region maps to a real metric', () {
      for (final id in muscleToMetric.values) {
        expect(() => metricById(id), returnsNormally,
            reason: 'muscleToMetric points at unknown metric "$id"');
      }
    });
  });

  group('Every ranked exercise/metric produces a valid rank', () {
    test('a plausible value yields a real tier and in-range percentile', () {
      for (final m in rankedMetrics) {
        final bw = m.bodyweightScaled ? 80.0 : null;
        final value = m.bodyweightScaled ? 80.0 : _probe(m.id);
        final res = eng.tierOf(m.id, value, bw);
        expect(eng.tiers.contains(res.tier), isTrue, reason: '${m.id} → unknown tier "${res.tier}"');
        expect(res.percentile, inInclusiveRange(0, 100), reason: '${m.id} percentile out of range');
        expect(res.rankValue, inInclusiveRange(0.0, 9.0), reason: '${m.id} rankValue out of range');
      }
    });

    test('strength lifts require bodyweight-at-time (throw without it)', () {
      for (final m in rankedMetrics.where((m) => m.bodyweightScaled)) {
        expect(() => eng.percentile(m.id, 80.0), throwsArgumentError,
            reason: '${m.id} must require a bodyweight snapshot');
      }
    });

    test('heavier load ⇒ higher percentile (monotonic) for every lift', () {
      for (final m in rankedMetrics.where((m) => m.bodyweightScaled)) {
        final lo = eng.percentile(m.id, 40, 80);
        final hi = eng.percentile(m.id, 120, 80);
        expect(hi, greaterThanOrEqualTo(lo), reason: '${m.id} not monotonic in load');
      }
    });
  });

  group('Weights / 1RM estimation', () {
    test('1 rep returns the weight itself', () => expect(eng.est1rm(100, 1), 100));
    test('more reps at same weight ⇒ higher estimated 1RM', () {
      expect(eng.est1rm(100, 5), greaterThan(eng.est1rm(100, 1)));
      expect(eng.est1rm(100, 8), greaterThan(eng.est1rm(100, 5)));
    });
    test('guards zero / non-positive input', () {
      expect(eng.est1rm(0, 5), 0);
      expect(eng.est1rm(100, 0), 0);
    });
    test('isolation lifts use rep-volume (weight×reps), compounds use est1rm', () {
      expect(eng.strengthValue('curl', 15, 12), 180); // rep-volume, not 1RM
      expect(eng.strengthValue('lateral_raise', 10, 15), 150);
      expect(eng.strengthValue('bench', 100, 5), eng.est1rm(100, 5)); // compound unchanged
    });
  });

  group('Direction handling (lower-is-better metrics)', () {
    test('resting HR: lower bpm ranks higher', () {
      expect(eng.percentile('resting_hr', 50), greaterThan(eng.percentile('resting_hr', 80)));
    });
    test('body fat: lower % ranks higher', () {
      expect(eng.percentile('body_fat_pct', 10), greaterThan(eng.percentile('body_fat_pct', 30)));
    });
  });

  group('Overall score', () {
    test('ignores unranked metrics and stays in range', () {
      final res = eng.overall([
        Log('bench', 80, bodyweight: 80),
        Log('vo2max', 50),
        Log('skin', 90),     // aesthetics, tracked — must be ignored
        Log('hair', 80),     // aesthetics, tracked — must be ignored
      ]);
      expect(eng.tiers.contains(res.tier), isTrue);
      expect(res.percentile, inInclusiveRange(0, 100));
    });
  });

  group('Category ranks', () {
    test('every ranked category appears (full roster, Wood until logged)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final cats = c.read(categoryRanksProvider);
      // Full-roster scoring shows ALL four ranked categories, even unfilled ones.
      for (final id in ['strength', 'performance', 'recovery', 'aesthetics']) {
        expect(cats.containsKey(id), isTrue);
      }
      for (final r in cats.values) {
        expect(eng.tiers.contains(r.tier), isTrue);
        expect(r.percentile, inInclusiveRange(0, 100));
      }
    });

    test('unfilled categories drag the overall below a single partially-filled one', () {
      final repo = InMemoryRepository();
      repo.saveLog('eye', Log('eye', -0.1, ts: '2026-06-27T12:00:00'));
      final c = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final cats = c.read(categoryRanksProvider);
      expect(cats.containsKey('aesthetics'), isTrue);
      // With only one aesthetic metric logged, the unfilled categories (worst-case) pull
      // the overall BELOW the aesthetics category rank — partial logging can't inflate it.
      expect(c.read(overallProvider).rankValue, lessThan(cats['aesthetics']!.rankValue));
      expect(c.read(overallProvider).rankValue, greaterThanOrEqualTo(0));
    });

    test('unrated metrics floor the score — one elite metric cannot inflate the overall', () {
      final repo = InMemoryRepository();
      repo.saveLog('eye', Log('eye', -0.25, ts: '2026-06-27T12:00:00')); // elite vision
      for (final id in ['bench', 'squat', 'ohp', 'pullup']) {
        repo.saveLog(id, Log(id, 40, bodyweight: 80, ts: '2026-06-27T12:00:00')); // weak lifts
      }
      final c = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final cats = c.read(categoryRanksProvider);
      final ov = c.read(overallProvider).rankValue;
      // The elite eye can't drag the overall up to its category level: the mostly-unfilled
      // roster + weak lifts floor it. And strength stays clearly weak.
      expect(ov, lessThan(cats['aesthetics']!.rankValue));
      expect(cats['strength']!.rankValue, lessThan(cats['aesthetics']!.rankValue));
    });
  });

  group('Persistence (survives restart)', () {
    test('a logged lift keeps its value, bodyweight & timestamp across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final repo1 = await PersistentRepository.create();
      repo1.saveLog('bench', Log('bench', 100, bodyweight: 82, ts: '2026-06-01T10:00:00.000'));
      await Future<void>.delayed(Duration.zero); // let the write-through flush

      // New instance = simulated app restart; reads from the persisted store.
      final repo2 = await PersistentRepository.create();
      final last = repo2.loadLogs()['bench']!.last;
      expect(last.value, 100);
      expect(last.bodyweight, 82);
      expect(last.ts, '2026-06-01T10:00:00.000');
    });
  });
}
