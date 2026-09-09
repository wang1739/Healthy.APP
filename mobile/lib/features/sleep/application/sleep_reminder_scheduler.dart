import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class SleepReminderSettings {
  const SleepReminderSettings({
    this.enabled = false,
    this.hour = 22,
    this.minute = 30,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.permissionDenied = false,
  });
  final bool enabled;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final bool permissionDenied;

  SleepReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? permissionDenied,
  }) => SleepReminderSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
    permissionDenied: permissionDenied ?? this.permissionDenied,
  );
}

DateTime nextSleepReminder({
  required DateTime now,
  required int weekday,
  required int hour,
  required int minute,
}) {
  var days = (weekday - now.weekday) % 7;
  var next = DateTime(now.year, now.month, now.day + days, hour, minute);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
  return next;
}

const _sleepIdBase = 300000000;
int sleepNotificationId(String accountKey, int weekday) {
  var hash = 0;
  for (final unit in accountKey.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _sleepIdBase + (hash % 10000000) * 10 + weekday;
}

bool isSleepNotificationId(int id) => id >= _sleepIdBase && id < 400000000;

class SleepReminderScheduler {
  SleepReminderScheduler({
    DateTime Function()? clock,
    Future<bool> Function()? requestPermission,
    Future<void> Function(int id, DateTime time, int weekday)? schedule,
    Future<void> Function(int id)? cancel,
    Future<void> Function()? openSettings,
    Future<SharedPreferences> Function()? preferences,
  }) : _clock = clock ?? DateTime.now,
       _permissionRequester = requestPermission,
       _scheduleCallback = schedule,
       _cancelCallback = cancel,
       _openSettingsCallback = openSettings,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static final instance = SleepReminderScheduler();
  static final openSleep = ValueNotifier<int>(0);
  final _notifications = FlutterLocalNotificationsPlugin();
  final DateTime Function() _clock;
  final Future<bool> Function()? _permissionRequester;
  final Future<void> Function(int id, DateTime time, int weekday)?
  _scheduleCallback;
  final Future<void> Function(int id)? _cancelCallback;
  final Future<void> Function()? _openSettingsCallback;
  final Future<SharedPreferences> Function() _preferences;
  bool _initialized = false;
  String? _activeAccount;

  String _prefix(String accountKey) => 'sleep_reminder_$accountKey';

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
        if (response.payload == 'sleep') openSleep.value++;
      },
    );
    _initialized = true;
  }

  Future<bool> requestNotificationPermission() async {
    if (_permissionRequester != null) return _permissionRequester();
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

  Future<void> openNotificationSettings() async {
    if (_openSettingsCallback != null) {
      await _openSettingsCallback();
      return;
    }
    try {
      await const MethodChannel('healthy/system_settings')
          .invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      await requestNotificationPermission();
    }
  }

  Future<SleepReminderSettings> load(String accountKey) async {
    final prefs = await _preferences();
    final prefix = _prefix(accountKey);
    return SleepReminderSettings(
      enabled: prefs.getBool('${prefix}_enabled') ?? false,
      hour: prefs.getInt('${prefix}_hour') ?? 22,
      minute: prefs.getInt('${prefix}_minute') ?? 30,
      weekdays:
          (prefs.getStringList('${prefix}_weekdays') ??
                  const ['1', '2', '3', '4', '5', '6', '7'])
              .map(int.parse)
              .toSet(),
      permissionDenied: prefs.getBool('${prefix}_permission_denied') ?? false,
    );
  }

  Future<SleepReminderSettings> save(
    String accountKey,
    SleepReminderSettings settings,
  ) async {
    if (settings.enabled && settings.weekdays.isEmpty) {
      throw const FormatException('请至少选择一天');
    }
    var value = settings;
    if (settings.enabled) {
      final allowed = await requestNotificationPermission();
      value = settings.copyWith(permissionDenied: !allowed, enabled: allowed);
    }
    final prefs = await _preferences();
    final prefix = _prefix(accountKey);
    await prefs.setBool('${prefix}_enabled', value.enabled);
    await prefs.setInt('${prefix}_hour', value.hour);
    await prefs.setInt('${prefix}_minute', value.minute);
    await prefs.setStringList(
      '${prefix}_weekdays',
      value.weekdays.map((day) => '$day').toList(),
    );
    await prefs.setBool('${prefix}_permission_denied', value.permissionDenied);
    await sync(accountKey, value);
    return value;
  }

  Future<void> sync(
    String accountKey, [
    SleepReminderSettings? settings,
  ]) async {
    _activeAccount = accountKey;
    await cancelAccount(accountKey);
    final value = settings ?? await load(accountKey);
    if (!value.enabled || value.weekdays.isEmpty) return;
    for (final weekday in value.weekdays) {
      final time = nextSleepReminder(
        now: _clock(),
        weekday: weekday,
        hour: value.hour,
        minute: value.minute,
      );
      final id = sleepNotificationId(accountKey, weekday);
      if (_scheduleCallback != null) {
        await _scheduleCallback(id, time, weekday);
      } else {
        await initialize();
        await _notifications.zonedSchedule(
          id: id,
          title: '轻食记睡前提醒',
          body: '该准备休息了，保持规律作息',
          scheduledDate: tz.TZDateTime.from(time, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'sleep_reminders',
              '睡前提醒',
              channelDescription: '轻食记的本地睡前提醒',
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: 'sleep',
        );
      }
    }
  }

  Future<void> cancelAccount(String accountKey) async {
    for (var weekday = 1; weekday <= 7; weekday++) {
      final id = sleepNotificationId(accountKey, weekday);
      if (_cancelCallback != null) {
        await _cancelCallback(id);
      } else {
        await initialize();
        await _notifications.cancel(id: id);
      }
    }
  }

  Future<void> cancelActiveAccount() async {
    if (_activeAccount != null) await cancelAccount(_activeAccount!);
    _activeAccount = null;
  }
}
