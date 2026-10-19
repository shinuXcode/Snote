import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules alarms in Android's notification manager, so they can fire while
/// Snote is backgrounded or the editor has been closed.
class AlarmNotificationService {
  AlarmNotificationService._();
  static final AlarmNotificationService instance = AlarmNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (error) {
      debugPrint('[Snote][Alarm] timezone lookup failed; using package default: $error');
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'snote_alarms',
      'Snote alarms',
      description: 'Scheduled reminders and alarms',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    _initialized = true;
  }

  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
    for (var day = 1; day <= 7; day++) {
      await _plugin.cancel(id: id * 10 + day);
    }
  }

  Future<void> schedule({
    required int id,
    required String title,
    required DateTime firstAt,
    required String repeat, // once, daily, custom
    List<int> weekdays = const <int>[],
    bool silent = false,
    String? soundUri,
  }) async {
    await initialize();
    await cancel(id);
    final customSound = soundUri?.trim().isNotEmpty == true ? soundUri!.trim() : null;
    final channelId = silent
        ? 'snote_alarms_silent'
        : customSound == null
            ? 'snote_alarms'
            : 'snote_alarm_\${base64Url.encode(utf8.encode(customSound)).replaceAll('=', '').substring(0, 20)}';
    if (customSound != null && !silent) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(AndroidNotificationChannel(
        channelId,
        'Snote alarms · custom sound',
        description: 'Scheduled reminders using the selected ringtone',
        importance: Importance.max,
        playSound: true,
        sound: UriAndroidNotificationSound(customSound),
        enableVibration: true,
      ));
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        silent ? 'Snote silent alarms' : 'Snote alarms',
        channelDescription: 'Scheduled reminders and alarms',
        importance: Importance.max,
        priority: Priority.max,
        playSound: !silent,
        sound: !silent && customSound != null ? UriAndroidNotificationSound(customSound) : null,
        enableVibration: !silent,
        category: AndroidNotificationCategory.alarm,
      ),
    );
    final now = tz.TZDateTime.now(tz.local);
    final first = tz.TZDateTime.from(firstAt, tz.local);
    if (repeat == 'daily') {
      var target = first;
      if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: 'Snote alarm',
        scheduledDate: target,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return;
    }
    if (repeat == 'custom' && weekdays.isNotEmpty) {
      for (final day in weekdays.toSet()) {
        final notificationId = id * 10 + day;
        var target = first;
        while (target.weekday != day || !target.isAfter(now)) {
          target = target.add(const Duration(days: 1));
        }
        await _plugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: 'Snote alarm',
          scheduledDate: target,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
      return;
    }
    var target = first;
    if (!target.isAfter(now)) target = now.add(const Duration(minutes: 1));
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: 'Snote alarm',
      scheduledDate: target,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> rescheduleAll(List<Map<String, Object?>> alarms) async {
    await initialize();
    for (final alarm in alarms) {
      if (alarm['enabled'] != true) continue;
      final id = (alarm['id'] as num?)?.toInt();
      final at = DateTime.tryParse(alarm['at']?.toString() ?? '');
      if (id == null || at == null) continue;
      if ((alarm['repeat']?.toString() ?? 'once') == 'once' && !at.isAfter(DateTime.now())) {
        alarm['enabled'] = false;
        continue;
      }
      final weekdays = (alarm['weekdays'] as List? ?? const <Object?>[])
          .whereType<num>().map((day) => day.toInt()).toList();
      await schedule(
        id: id,
        title: alarm['title']?.toString() ?? 'Snote alarm',
        firstAt: at,
        repeat: alarm['repeat']?.toString() ?? 'once',
        weekdays: weekdays,
        silent: alarm['silent'] == true,
        soundUri: alarm['soundUri']?.toString(),
      );
    }
  }
}
