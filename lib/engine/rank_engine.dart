// ════════════════════════════════════════════════════════════════════════
// Physical — Rank Engine (Dart port of physical_rank_engine.py v0.3)
//
// Pure, deterministic. Faithful port of the verified Python reference; the
// parity test (rank_engine_test.dart) asserts identical results against
// golden_vectors.json.
//
// v0.3: strength standards are a TWO-COMPONENT MIXTURE (untrained mass +
// trained tail), grounded in grip-strength norms + training prevalence.
// Carries: allometric BW scaling, distribution->percentile, derived thresholds,
// direction flag, z-space overall, and bodyweight-at-time log scoring.
// ════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

// ─── Tiers ───────────────────────────────────────────────────────────────
const List<String> tiers = [
  'Wood', 'Bronze', 'Silver', 'Gold', 'Platinum',
  'Diamond', 'Champion', 'Titan', 'Glory'
];
const Map<String, double> tierTopPct = {
  'Bronze': 80, 'Silver': 60, 'Gold': 40, 'Platinum': 20,
  'Diamond': 10, 'Champion': 3, 'Titan': 1, 'Glory': 0.1
};
const List<double> tierEntryP = [0.0, 0.20, 0.40, 0.60, 0.80, 0.90, 0.97, 0.99, 0.999];
const List<String> sub = ['I', 'II', 'III'];
const double _allo = 0.67;

// ─── Normal math (std-lib-free) ─────────────────────────────────────────────
double _erf(double x) {
  final sign = x < 0 ? -1.0 : 1.0;
  x = x.abs();
  final t = 1.0 / (1.0 + 0.3275911 * x);
  final y = 1.0 -
      (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                  0.284496736) * t + 0.254829592) * t * math.exp(-x * x);
  return sign * y;
}

double _normCdf(double x, double mu, double sigma) =>
    0.5 * (1 + _erf((x - mu) / (sigma * math.sqrt2)));

double _normInv(double p, double mu, double sigma) {
  p = p.clamp(1e-12, 1 - 1e-12);
  const a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
    1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00];
  const b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
    6.680131188771972e+01, -1.328068155288572e+01];
  const c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
    -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00];
  const d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
    3.754408661907416e+00];
  const plow = 0.02425, phigh = 1 - 0.02425;
  double x;
  if (p < plow) {
    final q = math.sqrt(-2 * math.log(p));
    x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  } else if (p <= phigh) {
    final q = p - 0.5, r = q * q;
    x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
        (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
  } else {
    final q = math.sqrt(-2 * math.log(1 - p));
    x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  return mu + sigma * x;
}

// ─── Distributions ──────────────────────────────────────────────────────────
abstract class Distribution {
  double cdf(double x);
  double quantile(double p);
}

class Dist implements Distribution {
  final String kind; // 'normal' | 'lognormal'
  final double mu, sigma;
  const Dist(this.kind, this.mu, this.sigma);

  @override
  double cdf(double x) {
    if (kind == 'normal') return _normCdf(x, mu, sigma);
    if (x <= 0) return 0.0;
    return _normCdf(math.log(x), mu, sigma);
  }

  @override
  double quantile(double p) {
    p = p.clamp(1e-9, 1 - 1e-9);
    final q = _normInv(p, mu, sigma);
    return kind == 'normal' ? q : math.exp(q);
  }
}

class MixtureDist implements Distribution {
  final List<(double, Distribution)> comps; // (weight, component)
  MixtureDist(this.comps);

  @override
  double cdf(double x) {
    var s = 0.0;
    for (final c in comps) {
      s += c.$1 * c.$2.cdf(x);
    }
    return s;
  }

  @override
  double quantile(double p) {
    p = p.clamp(1e-9, 1 - 1e-9);
    var lo = 1e-6, hi = 200.0;
    for (var i = 0; i < 70; i++) {
      final mid = (lo + hi) / 2;
      if (cdf(mid) < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }
}

Distribution _lognormFromMedianCv(double median, double cv) =>
    Dist('lognormal', math.log(median), math.sqrt(math.log(1 + cv * cv)));

class Standard {
  final String metricId;
  final int direction;
  final bool bodyweightScaled;
  final Distribution dist;
  final String source;
  final bool provisional;
  const Standard(this.metricId, this.direction, this.bodyweightScaled, this.dist,
      this.source, {this.provisional = true});
}

// Strength: untrained mass (grip-grounded CV) + trained tail (prevalence weight).
const double _refBw = 80.0;
const double _gripCv = 0.18, _pTrain = 0.22, _trCv = 0.30;

Standard _strengthMix(String mid, double unR, double trR, String note) {
  final sUn = (unR * math.pow(_refBw, 1 - _allo)).toDouble();
  final sTr = (trR * math.pow(_refBw, 1 - _allo)).toDouble();
  final dist = MixtureDist([
    (1 - _pTrain, _lognormFromMedianCv(sUn, _gripCv)),
    (_pTrain, _lognormFromMedianCv(sTr, _trCv)),
  ]);
  return Standard(mid, 1, true, dist, note);
}

// !! PROVISIONAL — see STANDARDS_METHODOLOGY.md. Tuning is a data edit. !!
final Map<String, Standard> standards = {
  'bench': _strengthMix('bench', 0.50, 1.15, 'mix untrained0.50/trained1.15'),
  'squat': _strengthMix('squat', 0.75, 1.60, 'mix untrained0.75/trained1.60'),
  'deadlift': _strengthMix('deadlift', 0.95, 2.00, 'mix untrained0.95/trained2.00'),
  'ohp': _strengthMix('ohp', 0.32, 0.70, 'mix untrained0.32/trained0.70'),
  'vo2max': const Standard('vo2max', 1, false, Dist('normal', 48.0, 9.0),
      'HUNT men 45.4±8.9, youth-nudged'),
  'resting_hr': const Standard('resting_hr', -1, false, Dist('normal', 70.0, 10.0),
      'genpop RHR ~70±10 (lower better)'),
  'plank': Standard('plank', 1, false, Dist('lognormal', math.log(80), 0.5),
      'plank hold sec (WKU norm, form-dependent)'),
  'vert': const Standard('vert', 1, false, Dist('normal', 43.0, 11.0),
      'CMJ-with-arms norms, genpop young male'),
  'run5k_kmh': Standard('run5k_kmh', 1, false, Dist('lognormal', math.log(8.5), 0.28),
      '5k speed vs general pop (selection-bias corrected), FLAG'),
  'hrv': Standard('hrv', 1, false, Dist('lognormal', math.log(50), 0.5),
      'HRV ms — method-dependent, FLAG'),
};

// ─── Core ───────────────────────────────────────────────────────────────────
double _score(Standard std, double value, double? bw) {
  if (std.bodyweightScaled) {
    if (bw == null || bw <= 0) {
      throw ArgumentError('${std.metricId} needs bodyweight-at-time');
    }
    return value / math.pow(bw, _allo);
  }
  return value;
}

double percentile(String metricId, double value, [double? bodyweight]) {
  final std = standards[metricId]!;
  final below = std.dist.cdf(_score(std, value, bodyweight));
  final p = std.direction == 1 ? below : 1.0 - below;
  return p.clamp(0.0, 1.0);
}

int _tierIdx(double p) {
  var idx = 0;
  for (var i = 0; i < tierEntryP.length; i++) {
    if (p >= tierEntryP[i]) idx = i;
  }
  return idx;
}

double _rankValueFromP(double p) {
  final idx = _tierIdx(p);
  final lo = tierEntryP[idx];
  final hi = idx + 1 < tierEntryP.length ? tierEntryP[idx + 1] : 1.0;
  final frac = hi <= lo ? 0.0 : ((p - lo) / (hi - lo)).clamp(0.0, 1.0);
  return idx + frac;
}

double rankValue(String metricId, double value, [double? bodyweight]) =>
    _rankValueFromP(percentile(metricId, value, bodyweight));

class RankResult {
  final String tier, sub;
  final double topPct, percentile, rankValue;
  RankResult(this.tier, this.sub, this.topPct, this.percentile, this.rankValue);
}

RankResult tierOf(String metricId, double value, [double? bodyweight]) {
  final p = percentile(metricId, value, bodyweight);
  final rv = _rankValueFromP(p);
  final idx = rv.floor();
  final si = ((rv - idx) * 3).floor().clamp(0, 2);
  return RankResult(tiers[idx], sub[si], (1 - p) * 100, p * 100, rv);
}

double threshold(String metricId, String tier, [double? bodyweight]) {
  final std = standards[metricId]!;
  final pEntry = tierEntryP[tiers.indexOf(tier)];
  final cdfP = std.direction == 1 ? pEntry : 1.0 - pEntry;
  final x = std.dist.quantile(cdfP);
  return std.bodyweightScaled ? x * math.pow(bodyweight!, _allo) : x;
}

class Log {
  final String metricId;
  final double value;
  final double? bodyweight;
  final String? ts;
  Log(this.metricId, this.value, {this.bodyweight, this.ts});
}

RankResult scoreLog(Log log) => tierOf(log.metricId, log.value, log.bodyweight);

RankResult overall(List<Log> logs) {
  final zs = <double>[];
  for (final log in logs) {
    if (!standards.containsKey(log.metricId)) continue;
    final p = percentile(log.metricId, log.value, log.bodyweight).clamp(1e-6, 1 - 1e-6);
    zs.add(_normInv(p, 0, 1));
  }
  if (zs.isEmpty) return RankResult('Wood', 'I', 99.9, 0.1, 0.0);
  final zbar = zs.reduce((a, b) => a + b) / zs.length;
  final pbar = _normCdf(zbar, 0, 1);
  final rv = _rankValueFromP(pbar);
  final idx = rv.floor();
  final si = ((rv - idx) * 3).floor().clamp(0, 2);
  return RankResult(tiers[idx], sub[si], (1 - pbar) * 100, pbar * 100, rv);
}

double est1rm(double weight, int reps) {
  if (reps <= 0 || weight <= 0) return 0;
  if (reps == 1) return weight;
  final r = math.min(reps, 12);
  final v = (weight * (1 + r / 30) +
          weight / (1.0278 - 0.0278 * r) +
          (100 * weight) / (101.3 - 2.67123 * r)) / 3;
  return (v * 100).round() / 100;
}
