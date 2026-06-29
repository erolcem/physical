// data/notifications.dart — proactive notifications (PDF Part 5/Table 3): a daily
// local reminder for each timed habit. The reminder-computation is pure (unit
// tested); the platform scheduling is guarded to iOS/Android so the Linux/web dev
// builds and tests are unaffected (no-op everywhere else).
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'habits.dart';

/// A daily reminder derived from a timed habit.
class HabitReminder {
  final int id;
  final String title;
  final int hour;
  final int minute;
  const HabitReminder(this.id, this.title, this.hour, this.minute);
}

/// Pure: the reminders to schedule for the current habits (timed ones only).
List<HabitReminder> habitReminders(List<Habit> habits) {
  final out = <HabitReminder>[];
  for (final h in habits) {
    final t = h.time;
    if (t == null) continue;
    final p = t.split(':');
    final hh = int.tryParse(p[0]);
    final mm = p.length > 1 ? int.tryParse(p[1]) : 0;
    if (hh == null || mm == null) continue;
    out.add(HabitReminder(h.id.hashCode & 0x7fffffff, h.title, hh, mm));
  }
  return out;
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get _supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> init() async {
    if (!_supported || _ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      // Fall back to UTC if the device timezone can't be resolved.
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _ready = true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('habits', 'Habit reminders',
        channelDescription: 'Daily reminders for your habits',
        importance: Importance.defaultImportance),
    iOS: DarwinNotificationDetails(),
  );

  /// Cancel and re-schedule daily reminders to match the current timed habits.
  Future<void> syncHabitReminders(List<Habit> habits) async {
    if (!_supported) return;
    if (!_ready) await init();
    await _plugin.cancelAll();
    const details = _details;
    for (final r in habitReminders(habits)) {
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, r.hour, r.minute);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        r.id, 'Physical', 'Time for: ${r.title}', when, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      );
    }
    await _scheduleAllNudges(); // re-apply cached AI nudges (cancelAll dropped them)
    // Fallback recap at 9pm only if no AI evening nudge is set (so the user still gets one).
    if (habits.isNotEmpty && !_nudges.containsKey(nudgeEveningId)) {
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        nudgeEveningId, 'Daily recap', 'How did today go? Review your habit checklist.',
        when, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  // AI nudge slots — morning (the day ahead) + evening (how today went).
  static const int nudgeMorningId = 990002;
  static const int nudgeEveningId = 990003;
  final Map<int, (String, int)> _nudges = {}; // id → (text, hour); cached across cancelAll

  /// Schedule a ONE-OFF AI-personalised nudge for the next [hour] under a slot [id]
  /// (refreshed each sync, so it never shows stale advice). No-op off iOS/Android or empty.
  Future<void> scheduleAiNudge(int id, String text, int hour) async {
    if (text.trim().isEmpty) return;
    _nudges[id] = (text.trim(), hour);
    await _scheduleNudge(id);
  }

  Future<void> _scheduleAllNudges() async {
    for (final id in _nudges.keys.toList()) {
      await _scheduleNudge(id);
    }
  }

  Future<void> _scheduleNudge(int id) async {
    final n = _nudges[id];
    if (!_supported || n == null) return;
    if (!_ready) await init();
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, n.$2);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id, 'Physical', n.$1, when, _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
