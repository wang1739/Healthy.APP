import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

List<DateTime> reminderSlots({
  required DateTime day,
  required DateTime now,
  required int startMinutes,
  required int endMinutes,
  required int intervalMinutes,
  int? quietStartMinutes,
  int? quietEndMinutes,
  bool targetReached = false,
}) {
  if (targetReached || intervalMinutes <= 0) return const [];
  final start = DateTime(
    day.year,
    day.month,
    day.day,
  ).add(Duration(minutes: startMinutes));
  var end = DateTime(
    day.year,
    day.month,
    day.day,
  ).add(Duration(minutes: endMinutes));
  if (endMinutes <= startMinutes) end = end.add(const Duration(days: 1));
  bool quiet(DateTime slot) {
    if (quietStartMinutes == null || quietEndMinutes == null) return false;
    final value = slot.hour * 60 + slot.minute;
    return quietStartMinutes <= quietEndMinutes
        ? value >= quietStartMinutes && value < quietEndMinutes
        : value >= quietStartMinutes || value < quietEndMinutes;
  }

  return [
    for (
      var slot = start;
      !slot.isAfter(end);
      slot = slot.add(Duration(minutes: intervalMinutes))
    )
      if (slot.isAfter(now) && !quiet(slot)) slot,
  ];
}

const _hydrationIdBase = 1200000000;
int hydrationNotificationId(String accountKey, DateTime slot) {
  var hash = 0;
  for (final unit in accountKey.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _hydrationIdBase +
      (hash ^ slot.millisecondsSinceEpoch ~/ 60000).abs() % 800000000;
}

bool isHydrationNotificationId(int id) =>
    id >= _hydrationIdBase && id < 2000000000;

class HydrationReminderScheduler {
  HydrationReminderScheduler({
    DateTime Function()? clock,
    this.scheduleNotification,
    this.cancelNotifications,
  }) : _clock = clock ?? DateTime.now;
  static final instance = HydrationReminderScheduler();
  static final openHydration = ValueNotifier<int>(0);
  final _notifications = FlutterLocalNotificationsPlugin();
  final DateTime Function() _clock;
  final Future<void> Function(int id, DateTime slot)? scheduleNotification;
  final Future<void> Function()? cancelNotifications;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == 'hydration') openHydration.value++;
      },
    );
    _initialized = true;
  }

  Future<String> timezoneName() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  Future<bool> requestPermission() async {
    await initialize();
    final android = await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final ios = await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    return android ?? ios ?? true;
  }

  Future<void> sync({
    required String accountKey,
    required HydrationDay day,
    DateTime? now,
  }) async {
    await cancelHydrationReminders();
    final settings = day.settings;
    if (!settings.reminderEnabled) return;
    int minutes(String value) {
      final parts = value.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final slots = reminderSlots(
      day: day.date,
      now: now ?? _clock(),
      startMinutes: minutes(settings.reminderStart),
      endMinutes: minutes(settings.reminderEnd),
      intervalMinutes: settings.reminderIntervalMinutes,
      quietStartMinutes: settings.quietStart == null
          ? null
          : minutes(settings.quietStart!),
      quietEndMinutes: settings.quietEnd == null
          ? null
          : minutes(settings.quietEnd!),
      targetReached: day.consumedMl >= day.targetMl,
    );
    for (final slot in slots) {
      if (scheduleNotification != null) {
        await scheduleNotification!(
          hydrationNotificationId(accountKey, slot),
          slot,
        );
        continue;
      }
      await initialize();
      await _notifications.zonedSchedule(
        id: hydrationNotificationId(accountKey, slot),
        title: '轻食记饮水提醒',
        body: '该喝杯水、活动一下啦',
        scheduledDate: tz.TZDateTime.from(slot, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'hydration_reminders',
            '饮水提醒',
            channelDescription: '轻食记的本地饮水提醒',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'hydration',
      );
    }
  }

  Future<void> cancelHydrationReminders() async {
    if (cancelNotifications != null) {
      await cancelNotifications!();
      return;
    }
    await initialize();
    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      if (isHydrationNotificationId(request.id)) {
        await _notifications.cancel(id: request.id);
      }
    }
  }
}
