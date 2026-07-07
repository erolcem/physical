// data/profile.dart — profile facts. AGE IS DERIVED: the user stores a date of
// birth once and the 'age' metric refreshes itself on birthdays, instead of
// freezing at whatever number was typed years ago. Pure + unit-tested.
import '../engine/rank_engine.dart' show Log;
import 'repository.dart';

/// Whole-year age on [today] for someone born [dob] (birthday not yet reached
/// this year → last year's age).
int ageOn(DateTime dob, {DateTime? today}) {
  final t = today ?? DateTime.now();
  var a = t.year - dob.year;
  if (t.month < dob.month || (t.month == dob.month && t.day < dob.day)) a--;
  return a < 0 ? 0 : a;
}

/// Re-derive the 'age' log from the stored DOB: appends a fresh log when the
/// derived age differs from the latest logged one (first run, or a birthday
/// passed). Returns the newly logged age, or null when nothing changed.
int? syncAgeFromDob(Repository repo, {DateTime? today}) {
  final dobIso = repo.loadDob();
  final dob = dobIso == null ? null : DateTime.tryParse(dobIso);
  if (dob == null) return null;
  final t = today ?? DateTime.now();
  final age = ageOn(dob, today: t);
  Log? latest;
  for (final l in (repo.loadLogs()['age'] ?? const <Log>[])) {
    if (latest == null || l.ts.compareTo(latest.ts) > 0) latest = l;
  }
  if (latest != null && latest.value.round() == age) return null;
  repo.saveLog('age', Log('age', age.toDouble(), ts: t.toIso8601String()));
  return age;
}
