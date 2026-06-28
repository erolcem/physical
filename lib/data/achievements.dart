// data/achievements.dart — the Trophy Room. Each time the OVERALL rank reaches a new
// personal-best tier+sub (e.g. Bronze III → Bronze II → Bronze I → Silver III …), that
// milestone is recorded as a trophy. Derived purely from the backfilled `overall_rank`
// history (rank_history.dart), so it reconstructs even after a fresh install + sync.
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log;

class Achievement {
  final String tier; // e.g. 'Gold'
  final String sub; // 'I' | 'II' | 'III'
  final String date; // YYYY-MM-DD first reached
  final int level; // tierIndex*3 + subIndex (0..26), for ordering
  const Achievement(this.tier, this.sub, this.date, this.level);
}

/// The ordered list of overall-rank milestones (oldest → newest). One entry per time
/// the running best crossed into a higher tier+sub; the date is when it was first seen.
List<Achievement> overallAchievements(List<Log> overallRankLogs) {
  final sorted = [...overallRankLogs]..sort((a, b) => a.ts.compareTo(b.ts));
  final out = <Achievement>[];
  var maxLevel = -1;
  for (final l in sorted) {
    final rv = l.value;
    final ti = rv.floor().clamp(0, eng.tiers.length - 1);
    final si = ((rv - ti) * 3).floor().clamp(0, 2);
    final level = ti * 3 + si;
    if (level > maxLevel) {
      out.add(Achievement(
          eng.tiers[ti], eng.sub[si], l.ts.length >= 10 ? l.ts.substring(0, 10) : l.ts, level));
      maxLevel = level;
    }
  }
  return out;
}
