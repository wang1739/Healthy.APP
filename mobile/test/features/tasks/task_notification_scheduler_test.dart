import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

TaskNotification _notification(String id, DateTime due, {int offset = 0}) =>
    TaskNotification(
      instanceId: id,
      title: '测试任务',
      currentLocalDate: DateTime(due.year, due.month, due.day),
      dueAt: due,
      reminderOffsetMinutes: offset,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('提前量换算并过滤过去及七天外通知', () {
    final now = DateTime(2026, 9, 10, 10);
    expect(
      taskReminderTime(
        _notification('a', DateTime(2026, 9, 10, 11), offset: 30),
      ),
      DateTime(2026, 9, 10, 10, 30),
    );
    expect(
      schedulableTaskNotifications(
        [
          _notification('past', DateTime(2026, 9, 10, 9)),
          _notification('ok', DateTime(2026, 9, 11, 9), offset: 15),
          _notification('late', DateTime(2026, 9, 18, 9)),
        ],
        now: now,
        settings: const TaskSettings(quietEnabled: false),
      ).map((item) => item.instanceId),
      ['ok'],
    );
  });

  test('跨午夜勿扰直接跳过且不会补发', () {
    const settings = TaskSettings(
      quietEnabled: true,
      quietStartTime: '22:30',
      quietEndTime: '07:00',
    );
    expect(isTaskQuietTime(DateTime(2026, 9, 10, 23), settings), isTrue);
    expect(isTaskQuietTime(DateTime(2026, 9, 11, 6, 59), settings), isTrue);
    expect(isTaskQuietTime(DateTime(2026, 9, 11, 7), settings), isFalse);
  });

  test('任务通知 ID 与饮水、睡眠隔离', () {
    final id = taskNotificationId('account', 'instance');
    expect(isTaskNotificationId(id), isTrue);
    expect(isHydrationNotificationId(id), isFalse);
    expect(isSleepNotificationId(id), isFalse);
  });

  test('同步只安排合格通知并上报，账号取消互不影响', () async {
    final scheduled = <({int id, String payload})>[];
    final cancelled = <int>[];
    final events = <String>[];
    final scheduler = TaskNotificationScheduler(
      clock: () => DateTime(2026, 9, 10, 10),
      loadNotifications: () async => [
        _notification('ok', DateTime(2026, 9, 10, 12), offset: 15),
        _notification('quiet', DateTime(2026, 9, 10, 23)),
      ],
      loadSettings: () async => const TaskSettings(),
      schedule: (id, time, title, payload) async =>
          scheduled.add((id: id, payload: payload)),
      cancel: (id) async => cancelled.add(id),
      reportEvents: (items) async =>
          events.addAll(items.map((item) => item['eventType'] as String)),
    );
    await scheduler.sync('a');
    await scheduler.cancelAccount('a');
    await scheduler.cancelAccount('b');

    expect(scheduled, hasLength(1));
    expect(scheduled.single.payload, 'ok');
    expect(events, contains('SCHEDULED'));
    expect(cancelled.where(isTaskNotificationId), isNotEmpty);
    expect(cancelled.where(isHydrationNotificationId), isEmpty);
  });

  test('仅首次启用任务提醒请求权限，拒绝不阻塞任务保存', () async {
    var requests = 0;
    final scheduler = TaskNotificationScheduler(
      requestPermission: () async {
        requests++;
        return false;
      },
    );
    expect(await scheduler.ensurePermission('a', enabling: false), isTrue);
    expect(await scheduler.ensurePermission('a', enabling: true), isFalse);
    expect(await scheduler.ensurePermission('a', enabling: true), isFalse);
    expect(requests, 1);
    expect(await scheduler.permissionDenied('a'), isTrue);
  });

  test('点击负载只含实例标识并上报 OPENED 后导航到日期', () async {
    final events = <Map<String, dynamic>>[];
    final scheduler = TaskNotificationScheduler(
      reportEvents: (items) async => events.addAll(items),
    );
    await scheduler.rememberTaskDate('a', 'i1', DateTime(2026, 9, 10));
    await scheduler.handleOpened('a', 'i1');

    expect(TaskNotificationScheduler.openTask.value?.instanceId, 'i1');
    expect(
      TaskNotificationScheduler.openTask.value?.date,
      DateTime(2026, 9, 10),
    );
    expect(events.single['eventType'], 'OPENED');
    expect(events.single['deviceKeyHash'], matches(r'^[0-9a-f]{64}$'));
    expect(events.single['occurredAt'], isNotEmpty);
    expect(events.single['idempotencyKey'], isNotEmpty);
  });
}
