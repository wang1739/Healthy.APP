import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';

void main() {
  test('解析模板、实例、每日汇总与可解释健康来源', () {
    final day = TaskDay.fromJson({
      'date': '2026-09-10',
      'status': 'READY',
      'summary': {
        'totalCount': 4,
        'completedCount': 1,
        'pendingCount': 2,
        'overdueCount': 1,
        'nextTaskId': 'i1',
      },
      'timeline': [
        {
          'id': 'i1',
          'templateId': 't1',
          'templateVersion': 3,
          'title': '记录早餐',
          'note': '完成后自动更新',
          'source': 'PLAN',
          'category': 'HEALTH',
          'priority': 'IMPORTANT',
          'status': 'COMPLETED',
          'completionSource': 'AUTO_HEALTH_DATA',
          'completionReason': '已记录早餐',
          'originalLocalDate': '2026-09-10',
          'currentLocalDate': '2026-09-10',
          'currentDueAt': '2026-09-10T00:00:00Z',
          'allDay': false,
          'reminderOffsetMinutes': 15,
          'recurrenceType': 'DAILY',
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'postponeCount': 0,
          'overdue': false,
          'hasPlanUpdate': true,
        },
      ],
      'allDay': [
        {
          'id': 'i2',
          'title': '整理书桌',
          'source': 'USER',
          'category': 'LIFE',
          'priority': 'NORMAL',
          'status': 'PENDING',
          'currentLocalDate': '2026-09-10',
          'allDay': true,
        },
      ],
      'completed': const [],
      'skipped': const [],
    });

    expect(day.summary.totalCount, 4);
    expect(day.timeline.single.category.label, '健康');
    expect(day.timeline.single.completed, isTrue);
    expect(
      day.timeline.single.completionSource,
      TaskCompletionSource.autoHealthData,
    );
    expect(day.timeline.single.completionReason, '已记录早餐');
    expect(day.timeline.single.templateVersion, 3);
    expect(day.allDay.single.source.label, '我创建的');
  });

  test('未知枚举安全降级，未知状态不误判为完成', () {
    final task = TaskInstance.fromJson({
      'id': 'x',
      'title': '未知任务',
      'category': 'FUTURE_CATEGORY',
      'priority': 'FUTURE_PRIORITY',
      'source': 'FUTURE_SOURCE',
      'status': 'FUTURE_STATUS',
      'currentLocalDate': '2026-09-10',
    });

    expect(task.category, TaskCategory.other);
    expect(task.category.label, '其他');
    expect(task.status, TaskStatus.unknown);
    expect(task.completed, isFalse);
    expect(task.priority, TaskPriority.normal);
  });

  test('解析七天统计、勿扰设置和通知安排', () {
    final week = TaskWeek.fromJson({
      'startDate': '2026-09-04',
      'endDate': '2026-09-10',
      'expectedCount': 10,
      'completedCount': 6,
      'skippedCount': 1,
      'postponedCount': 2,
      'overdueCount': 1,
      'completionRate': 0.6,
      'categories': [
        {'category': 'WORK', 'expectedCount': 5, 'completedCount': 4},
      ],
    });
    final emptyWeek = TaskWeek.fromJson({
      'startDate': '2026-09-04',
      'endDate': '2026-09-10',
      'expectedCount': 0,
    });
    final settings = TaskSettings.fromJson({
      'quietEnabled': true,
      'quietStartTime': '22:30',
      'quietEndTime': '07:00',
      'version': 2,
      'notificationPermissionDenied': true,
    });
    final notification = TaskNotification.fromJson({
      'instanceId': 'i1',
      'title': '开会',
      'currentLocalDate': '2026-09-10',
      'dueAt': '2026-09-10T02:00:00Z',
      'reminderOffsetMinutes': 30,
    });

    expect(week.categories.single.category, TaskCategory.work);
    expect(week.completionRate, 0.6);
    expect(emptyWeek.completionRate, isNull);
    expect(settings.quietStartMinutes, 22 * 60 + 30);
    expect(settings.quietEndMinutes, 7 * 60);
    expect(settings.version, 2);
    expect(notification.instanceId, 'i1');
    expect(notification.reminderOffsetMinutes, 30);

    final serverNotification = TaskNotification.fromJson({
      'instanceId': 'i2',
      'title': '散步',
      'dueAt': '2026-09-10T12:00:00Z',
      'notifyAt': '2026-09-10T11:45:00Z',
    });
    expect(serverNotification.dueAt, DateTime.parse('2026-09-10T11:45:00Z'));
    expect(serverNotification.currentLocalDate.year, 2026);
  });

  test('模板序列化不包含用户、完成率或健康条件结果', () {
    const draft = TaskDraft(
      title: '学习 Flutter',
      category: TaskCategory.study,
      priority: TaskPriority.urgent,
      allDay: false,
      recurrence: TaskRecurrence.weeklyDays,
      weekdays: {2, 4},
      reminderOffsetMinutes: 5,
    );
    final json = draft.toJson();

    expect(json['title'], '学习 Flutter');
    expect(json['category'], 'STUDY');
    expect(json['recurrenceType'], 'WEEKLY_DAYS');
    expect(json['weekdaysMask'], 10);
    expect(json, isNot(contains('weekdays')));
    expect(json, isNot(contains('userId')));
    expect(json, isNot(contains('completionRate')));
    expect(json, isNot(contains('healthConditionMet')));
  });
}
