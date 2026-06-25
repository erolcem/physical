// data/correlation.dart — the "strategic correlations" engine (PDF Part 5/Table 3).
// Pure Pearson correlation over two metrics' day-aligned values, plus a tiny model
// for a correlation the coach (or user) pins to the dashboard. Unit-tested.
import 'dart:math' as math;

import '../engine/rank_engine.dart' show Log;

/// Pearson r of two equal-length series. 0 if <2 points or no variance.
double pearson(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 2 || ys.length != n) return 0;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - mx, dy = ys[i] - my;
    sxy += dx * dy;
    sxx += dx * dx;
    syy += dy * dy;
  }
  if (sxx == 0 || syy == 0) return 0;
  return sxy / (math.sqrt(sxx) * math.sqrt(syy));
}

/// Align two metrics' logs by calendar day (last value per day) → paired series.
(List<double>, List<double>) alignByDay(List<Log> a, List<Log> b) {
  Map<String, double> byDay(List<Log> ls) =>
      {for (final l in ls) l.ts.substring(0, 10): l.value};
  final ma = byDay(a), mb = byDay(b);
  final days = ma.keys.where(mb.containsKey).toList()..sort();
  return ([for (final d in days) ma[d]!], [for (final d in days) mb[d]!]);
}

/// Correlation r between two metrics from their logs (null if too little overlap).
double? correlationOf(List<Log> a, List<Log> b) {
  final (xs, ys) = alignByDay(a, b);
  if (xs.length < 3) return null; // need a few overlapping days to be meaningful
  return pearson(xs, ys);
}

/// A correlation pair pinned to the dashboard.
class PinnedCorrelation {
  final String a;
  final String b;
  const PinnedCorrelation(this.a, this.b);

  /// Order-independent key so (a,b) and (b,a) are the same pin.
  String get key => ([a, b]..sort()).join('|');

  Map<String, dynamic> toJson() => {'a': a, 'b': b};
  factory PinnedCorrelation.fromJson(Map<String, dynamic> j) =>
      PinnedCorrelation(j['a'] as String, j['b'] as String);
}

/// Plain-language strength label for a correlation coefficient.
String correlationLabel(double r) {
  final a = r.abs();
  final dir = r >= 0 ? 'positive' : 'negative';
  if (a >= 0.7) return 'strong $dir';
  if (a >= 0.4) return 'moderate $dir';
  if (a >= 0.2) return 'weak $dir';
  return 'no clear';
}
