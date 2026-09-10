import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

DateTime taskReminderTime(TaskNotification value) =>
    value.dueAt.subtract(Duration(minutes: value.reminderOffsetMinutes));

bool isTaskQuietTime(DateTime time, TaskSettings settings) {
  if (!settings.quietEnabled) return false;
  final local = time.toLocal();
  final minutes = local.hour * 60 + local.minute;
  final start = settings.quietStartMinutes;
  final end = settings.quietEndMinutes;
  return start <= end
      ? minutes >= start && minutes < end
      : minutes >= start || minutes < end;
}

List<TaskNotification> schedulableTaskNotifications(
  Iterable<TaskNotification> values, {
  required DateTime now,
  required TaskSettings settings,
}) {
  final end = now.add(const Duration(days: 7));
  return values
      .where((value) {
        final reminder = taskReminderTime(value);
        return reminder.isAfter(now) &&
            !reminder.isAfter(end) &&
            !isTaskQuietTime(reminder, settings);
      })
      .toList(growable: false);
}

const _taskIdBase = 400000000;
int taskNotificationId(String accountKey, String instanceId) {
  var hash = 0x811c9dc5;
  for (final unit in '$accountKey:$instanceId'.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return _taskIdBase + hash % 100000000;
}

bool isTaskNotificationId(int id) => id >= _taskIdBase && id < 500000000;

class TaskNotificationTarget {
  const TaskNotificationTarget({required this.instanceId, required this.date});
  final String instanceId;
  final DateTime date;
}

class TaskNotificationScheduler {
  TaskNotificationScheduler({
    ApiClient? api,
    DateTime Function()? clock,
    Future<List<TaskNotification>> Function()? loadNotifications,
    Future<TaskSettings> Function()? loadSettings,
    Future<bool> Function()? requestPermission,
    Future<void> Function(int, DateTime, String, String)? schedule,
    Future<void> Function(int)? cancel,
    Future<void> Function(List<Map<String, dynamic>>)? reportEvents,
    Future<void> Function()? openSettings,
    Future<SharedPreferences> Function()? preferences,
  }) : _api = api ?? ApiClient.instance,
       _clock = clock ?? DateTime.now,
       _notificationLoader = loadNotifications,
       _settingsLoader = loadSettings,
       _permissionRequester = requestPermission,
       _scheduleCallback = schedule,
       _cancelCallback = cancel,
       _reportCallback = reportEvents,
       _openSettingsCallback = openSettings,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static final instance = TaskNotificationScheduler();
  static final openTask = ValueNotifier<TaskNotificationTarget?>(null);

  final ApiClient _api;
  final DateTime Function() _clock;
  final Future<List<TaskNotification>> Function()? _notificationLoader;
  final Future<TaskSettings> Function()? _settingsLoader;
  final Future<bool> Function()? _permissionRequester;
  final Future<void> Function(int, DateTime, String, String)? _scheduleCallback;
  final Future<void> Function(int)? _cancelCallback;
  final Future<void> Function(List<Map<String, dynamic>>)? _reportCallback;
  final Future<void> Function()? _openSettingsCallback;
  final Future<SharedPreferences> Function() _preferences;
  final _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _activeAccount;
  String? _pendingInstance;

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
        final account = _activeAccount;
        final instance = response.payload;
        if (account != null && instance != null) {
          handleOpened(account, instance);
        }
      },
    );
    final launch = await _notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _pendingInstance = launch?.notificationResponse?.payload;
    }
    _initialized = true;
  }

  Future<bool> ensurePermission(
    String accountKey, {
    required bool enabling,
  }) async {
    if (!enabling) return true;
    final prefs = await _preferences();
    final requestedKey = 'task_permission_requested_$accountKey';
    final deniedKey = 'task_permission_denied_$accountKey';
    if (prefs.getBool(requestedKey) == true) {
      return prefs.getBool(deniedKey) != true;
    }
    final allowed = await _requestPermission();
    await prefs.setBool(requestedKey, true);
    await prefs.setBool(deniedKey, !allowed);
    return allowed;
  }

  Future<bool> permissionDenied(String accountKey) async =>
      (await _preferences()).getBool('task_permission_denied_$accountKey') ==
      true;

  Future<bool> _requestPermission() async {
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
      await _requestPermission();
    }
  }

  Future<void> sync(String accountKey) async {
    try {
      await _sync(accountKey);
    } catch (_) {
      // Task and settings APIs remain usable when local scheduling fails.
    }
  }

  Future<void> _sync(String accountKey) async {
    _activeAccount = accountKey;
    final pending = _pendingInstance;
    if (pending != null) {
      _pendingInstance = null;
      await handleOpened(accountKey, pending);
    }
    await cancelAccount(accountKey);
    final now = _clock();
    final values = _notificationLoader != null
        ? await _notificationLoader()
        : await _api.getTaskNotifications(
            from: now,
            to: now.add(const Duration(days: 7)),
          );
    final settings = _settingsLoader != null
        ? await _settingsLoader()
        : await _api.getTaskSettings();
    final scheduled = schedulableTaskNotifications(
      values,
      now: now,
      settings: settings,
    );
    final stored = <String>[];
    final events = <Map<String, dynamic>>[];
    for (final value in scheduled) {
      final id = taskNotificationId(accountKey, value.instanceId);
      final time = taskReminderTime(value);
      if (_scheduleCallback != null) {
        await _scheduleCallback(id, time, value.title, value.instanceId);
      } else {
        await initialize();
        await _notifications.zonedSchedule(
          id: id,
          title: '任务提醒',
          body: value.title,
          scheduledDate: tz.TZDateTime.from(time, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminders',
              '任务提醒',
              channelDescription: '轻食记的每日任务提醒',
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: value.instanceId,
        );
      }
      stored.add('$id|${value.instanceId}');
      await rememberTaskDate(
        accountKey,
        value.instanceId,
        value.currentLocalDate,
      );
      events.add({
        'instanceId': value.instanceId,
        'eventType': 'SCHEDULED',
        'scheduledFor': time.toUtc().toIso8601String(),
      });
    }
    await (await _preferences()).setStringList(
      'task_scheduled_$accountKey',
      stored,
    );
    await _report(events);
  }

  Future<void> cancelAccount(String accountKey) async {
    final prefs = await _preferences();
    final key = 'task_scheduled_$accountKey';
    final stored = prefs.getStringList(key) ?? const [];
    final events = <Map<String, dynamic>>[];
    for (final item in stored) {
      final parts = item.split('|');
      final id = int.tryParse(parts.first);
      if (id == null || !isTaskNotificationId(id)) continue;
      if (_cancelCallback != null) {
        await _cancelCallback(id);
      } else {
        await initialize();
        await _notifications.cancel(id: id);
      }
      if (parts.length > 1) {
        events.add({'instanceId': parts[1], 'eventType': 'CANCELLED'});
      }
    }
    await prefs.remove(key);
    await _report(events);
  }

  Future<void> cancelActiveAccount() async {
    final account = _activeAccount;
    if (account != null) await cancelAccount(account);
    _activeAccount = null;
  }

  Future<void> rememberTaskDate(
    String accountKey,
    String instanceId,
    DateTime date,
  ) async {
    await (await _preferences()).setString(
      'task_notification_date_${accountKey}_$instanceId',
      formatLocalDate(date),
    );
  }

  Future<void> handleOpened(String accountKey, String instanceId) async {
    final raw = (await _preferences()).getString(
      'task_notification_date_${accountKey}_$instanceId',
    );
    final date = DateTime.tryParse(raw ?? '') ?? _clock();
    openTask.value = TaskNotificationTarget(
      instanceId: instanceId,
      date: DateTime(date.year, date.month, date.day),
    );
    await _report([
      {'instanceId': instanceId, 'eventType': 'OPENED'},
    ]);
  }

  Future<void> _report(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;
    try {
      final prefs = await _preferences();
      const deviceKey = 'task_notification_device_hash';
      var deviceHash = prefs.getString(deviceKey);
      if (deviceHash == null) {
        const hex = '0123456789abcdef';
        final random = Random.secure();
        deviceHash = List.generate(64, (_) => hex[random.nextInt(16)]).join();
        await prefs.setString(deviceKey, deviceHash);
      }
      final occurredAt = _clock().toUtc().toIso8601String();
      final enriched = events
          .map(
            (event) => {
              ...event,
              'deviceKeyHash': deviceHash,
              'occurredAt': occurredAt,
              'idempotencyKey':
                  '${_clock().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
            },
          )
          .toList(growable: false);
      if (_reportCallback != null) {
        await _reportCallback(enriched);
      } else {
        await _api.reportTaskNotificationEvents(
          enriched,
          idempotencyKey:
              '${_clock().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
        );
      }
    } catch (_) {
      // Notification audit is best-effort and cannot block local task use.
    }
  }
}
