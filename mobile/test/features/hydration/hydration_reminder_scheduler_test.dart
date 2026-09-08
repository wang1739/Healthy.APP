import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';

void main() {
  test('生成未来时段并排除勿扰时间', () {
    final slots = reminderSlots(
      day: DateTime(2026, 9, 8),
      now: DateTime(2026, 9, 8, 9, 30),
      startMinutes: 8 * 60,
      endMinutes: 20 * 60,
      intervalMinutes: 120,
      quietStartMinutes: 12 * 60,
      quietEndMinutes: 14 * 60,
    );
    expect(slots.map((e) => e.hour), [10, 14, 16, 18, 20]);
  });

  test('跨午夜范围、达标与次日', () {
    final slots = reminderSlots(
      day: DateTime(2026, 9, 8),
      now: DateTime(2026, 9, 8, 23),
      startMinutes: 22 * 60,
      endMinutes: 2 * 60,
      intervalMinutes: 120,
    );
    expect(slots, [DateTime(2026, 9, 9), DateTime(2026, 9, 9, 2)]);
    expect(
      reminderSlots(
        day: DateTime(2026, 9, 8),
        now: DateTime(2026, 9, 8),
        startMinutes: 8 * 60,
        endMinutes: 20 * 60,
        intervalMinutes: 60,
        targetReached: true,
      ),
      isEmpty,
    );
  });

  test('通知编号按账号和时段稳定且分组可识别', () {
    final slot = DateTime(2026, 9, 8, 10);
    expect(
      hydrationNotificationId('a', slot),
      hydrationNotificationId('a', slot),
    );
    expect(
      isHydrationNotificationId(hydrationNotificationId('a', slot)),
      isTrue,
    );
  });

  test('设置变化会取消旧提醒并按构造函数测试缝隙重排', () async {
    var cancelled = 0;
    final scheduled = <DateTime>[];
    final scheduler = HydrationReminderScheduler(
      clock: () => DateTime(2026, 9, 8, 9),
      cancelNotifications: () async => cancelled++,
      scheduleNotification: (id, slot) async => scheduled.add(slot),
    );
    await scheduler.sync(
      accountKey: 'user-a',
      day: HydrationDay.fromJson({
        'date': '2026-09-08',
        'status': 'EMPTY',
        'consumedMl': 0,
        'targetMl': 2000,
        'remainingMl': 2000,
        'progress': 0,
        'settings': {
          'effectiveTargetMl': 2000,
          'defaultCupMl': 250,
          'reminderEnabled': true,
          'reminderStartTime': '08:00',
          'reminderEndTime': '12:00',
          'reminderIntervalMinutes': 120,
        },
        'entries': [],
      }),
    );
    expect(cancelled, 1);
    expect(scheduled, [DateTime(2026, 9, 8, 10), DateTime(2026, 9, 8, 12)]);
  });
}
