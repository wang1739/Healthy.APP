import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('计算本周或下周的下一次提醒', () {
    expect(
      nextSleepReminder(
        now: DateTime(2026, 9, 9, 21),
        weekday: 3,
        hour: 22,
        minute: 30,
      ),
      DateTime(2026, 9, 9, 22, 30),
    );
    expect(
      nextSleepReminder(
        now: DateTime(2026, 9, 9, 23),
        weekday: 3,
        hour: 22,
        minute: 30,
      ),
      DateTime(2026, 9, 16, 22, 30),
    );
  });

  test('账号设置隔离，变化会只取消并重排本账号睡眠提醒', () async {
    final scheduled = <int>[];
    final cancelled = <int>[];
    final scheduler = SleepReminderScheduler(
      clock: () => DateTime(2026, 9, 9, 20),
      requestPermission: () async => true,
      schedule: (id, time, weekday) async => scheduled.add(id),
      cancel: (id) async => cancelled.add(id),
    );
    await scheduler.save(
      'a',
      const SleepReminderSettings(enabled: true, weekdays: {1, 3}, hour: 22),
    );
    await scheduler.save(
      'b',
      const SleepReminderSettings(enabled: false, weekdays: {5}),
    );
    expect((await scheduler.load('a')).enabled, isTrue);
    expect((await scheduler.load('b')).enabled, isFalse);
    expect(scheduled, hasLength(2));
    expect(cancelled.where(isSleepNotificationId), hasLength(14));
    expect(cancelled.where(isHydrationNotificationId), isEmpty);
  });

  test('开启时才请求权限，拒绝后关闭但保留设置状态', () async {
    var requests = 0;
    final scheduler = SleepReminderScheduler(
      requestPermission: () async {
        requests++;
        return false;
      },
      cancel: (_) async {},
    );
    await scheduler.save('a', const SleepReminderSettings(enabled: false));
    expect(requests, 0);
    final denied = await scheduler.save(
      'a',
      const SleepReminderSettings(enabled: true, weekdays: {1}),
    );
    expect(requests, 1);
    expect(denied.enabled, isFalse);
    expect(denied.permissionDenied, isTrue);
  });

  test('开启且未选择星期时拒绝保存', () async {
    final scheduler = SleepReminderScheduler(cancel: (_) async {});
    expect(
      () => scheduler.save(
        'a',
        const SleepReminderSettings(enabled: true, weekdays: {}),
      ),
      throwsFormatException,
    );
  });

  test('权限拒绝后可进入系统通知设置', () async {
    var opened = false;
    final scheduler = SleepReminderScheduler(
      openSettings: () async => opened = true,
    );

    await scheduler.openNotificationSettings();

    expect(opened, isTrue);
  });
}
