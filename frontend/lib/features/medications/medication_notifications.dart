import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class MedicationNotifications {
  MedicationNotifications._();
  static final instance = MedicationNotifications._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<bool>? _initializing;

  Future<bool> _initialize() {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return Future.value(false);
    }
    if (_initialized) return Future.value(true);
    final pending = _initializing ??= _initializeOnce();
    return pending.catchError((Object error) {
      _initializing = null;
      throw error;
    });
  }

  Future<bool> _initializeOnce() async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    final success = await _plugin.initialize(settings);
    if (success != true) return false;
    _initialized = true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: false, sound: true);
    final macos = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macos?.requestPermissions(alert: true, badge: false, sound: true);
    return true;
  }

  Future<void> schedule({
    required int id,
    required String name,
    String? instructions,
    required List<TimeOfDay> times,
    required Set<int> weekdays,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (id <= 0 || !await _initialize()) return;
    await cancel(id);
    if (weekdays.isEmpty) return;
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'medication_reminders',
        'Rappels de médicaments',
        channelDescription: 'Rappels locaux des prises programmées',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );
    final body = instructions == null || instructions.trim().isEmpty
        ? '$name — pensez à noter votre prise.'
        : '$name — ${instructions.trim()}';
    final now = tz.TZDateTime.now(tz.local);
    final earliest = startDate == null
        ? now
        : tz.TZDateTime(
            tz.local, startDate.year, startDate.month, startDate.day);
    final latest = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day);
    if (latest == null) {
      for (final day in weekdays) {
        for (var index = 0; index < times.length; index++) {
          final time = times[index];
          var first = earliest.isBefore(now) ? now : earliest;
          while (first.weekday != day ||
              (first.year == now.year &&
                  first.month == now.month &&
                  first.day == now.day &&
                  (first.hour > time.hour ||
                      (first.hour == time.hour &&
                          first.minute >= time.minute)))) {
            first = first.add(const Duration(days: 1));
          }
          final scheduled = tz.TZDateTime(
            tz.local,
            first.year,
            first.month,
            first.day,
            time.hour,
            time.minute,
          );
          await _plugin.zonedSchedule(
            _notificationId(id, day, index),
            'Rappel de médicament',
            body,
            scheduled,
            details,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.wallClockTime,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: 'medication:$id',
          );
        }
      }
    } else {
      // Finite treatments use dated notifications so they never repeat past
      // the prescribed end date. The 14-day window is refreshed on list load.
      for (var offset = 0; offset < 14; offset++) {
        final date = now.add(Duration(days: offset));
        if (date.isBefore(earliest) ||
            DateTime(date.year, date.month, date.day).isAfter(latest) ||
            !weekdays.contains(date.weekday)) {
          continue;
        }
        for (var index = 0; index < times.length; index++) {
          final time = times[index];
          final scheduled = tz.TZDateTime(
            tz.local,
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          if (!scheduled.isAfter(now)) continue;
          await _plugin.zonedSchedule(
            _datedNotificationId(id, date, index),
            'Rappel de médicament',
            body,
            scheduled,
            details,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.wallClockTime,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: 'medication:$id',
          );
        }
      }
    }
  }

  Future<void> scheduleSnooze({
    required int medicationId,
    required int reminderId,
    required String name,
    String? instructions,
    required DateTime snoozedUntil,
  }) async {
    if (medicationId <= 0 || reminderId <= 0 || !await _initialize()) return;
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'medication_reminders',
        'Rappels de médicaments',
        channelDescription: 'Rappels locaux des prises programmées',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );
    final instructionText = instructions?.trim();
    final body = instructionText == null || instructionText.isEmpty
        ? '$name — pensez à noter votre prise.'
        : '$name — $instructionText';
    await _plugin.zonedSchedule(
      _snoozeNotificationId(medicationId, reminderId),
      'Rappel de médicament reporté',
      body,
      tz.TZDateTime.from(snoozedUntil, tz.local),
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'medication:$medicationId',
    );
  }

  Future<void> cancelSnooze(int medicationId, int reminderId) async {
    if (medicationId <= 0 || reminderId <= 0 || !await _initialize()) return;
    await _plugin.cancel(_snoozeNotificationId(medicationId, reminderId));
  }

  Future<void> cancel(int medicationId) async {
    if (medicationId <= 0 || !await _initialize()) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload == 'medication:$medicationId') {
        await _plugin.cancel(request.id);
      }
    }
  }

  int _notificationId(int medicationId, int weekday, int timeIndex) =>
      ((medicationId * 31 + weekday) * 7 + timeIndex) & 0x7fffffff;

  int _datedNotificationId(int medicationId, DateTime date, int timeIndex) =>
      Object.hash(medicationId, date.year, date.month, date.day, timeIndex) &
      0x7fffffff;

  int _snoozeNotificationId(int medicationId, int reminderId) =>
      Object.hash(medicationId, reminderId, 'snooze') & 0x7fffffff;
}
