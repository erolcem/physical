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
    // A daily end-of-day accountability nudge to review the checklist (only if any habits).
    if (habits.isNotEmpty) {
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        _recapId, 'Daily recap', 'How did today go? Review your habit checklist.',
        when, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
    await _scheduleNudge(); // re-apply the cached AI nudge (cancelAll dropped it)
  }

  static const int _recapId = 990001; // fixed id for the daily recap reminder
  static const int _nudgeId = 990002; // fixed id for the AI personalised nudge
  String? _lastNudge; // cached so syncHabitReminders' cancelAll doesn't drop it
  int _nudgeHour = 8;

  /// Schedule a ONE-OFF AI-personalised nudge for the next [hour] (refreshed each sync
  /// with fresh text, so it never shows stale advice). No-op off iOS/Android or if empty.
  Future<void> scheduleAiNudge(String text, {int hour = 8}) async {
    if (text.trim().isEmpty) return;
    _lastNudge = text.trim();
    _nudgeHour = hour;
    await _scheduleNudge();
  }

  Future<void> _scheduleNudge() async {
    final t = _lastNudge;
    if (!_supported || t == null) return;
    if (!_ready) await init();
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, _nudgeHour);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      _nudgeId, 'Physical', t, when, _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
