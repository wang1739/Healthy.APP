import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/today/domain/today_data.dart';

Map<String, dynamic> response() => {
  'date': '2026-09-08',
  'plan': {
    'status': 'READY',
    'state': 'ACTIVE',
    'currentWeek': 2,
    'targetKcal': 1470,
    'proteinG': 110,
    'carbsG': 155,
    'fatG': 45,
    'waterMl': 1900,
    'exerciseDays': 4,
    'exerciseMinutes': 150,
    'sleepHours': 8,
  },
  'weight': {
    'status': 'READY',
    'valueKg': 62.5,
    'measuredAt': '2026-09-07T08:30:00Z',
  },
  'nutrition': {'status': 'COMING_SOON'},
  'hydration': {'status': 'EMPTY'},
  'activity': {'status': 'ERROR', 'message': '该项数据暂时无法加载'},
  'sleep': {'status': 'READY'},
  'tasks': {'status': 'COMING_SOON'},
  'nextAction': {'type': 'VIEW_PLAN', 'title': '查看今日目标'},
};

void main() {
  test('解析完整今日聚合响应与四种模块状态', () {
    final data = TodayData.fromJson(response());

    expect(data.date, DateTime(2026, 9, 8));
    expect(data.plan.status, TodayModuleStatus.ready);
    expect(data.plan.targetKcal, 1470);
    expect(data.weight.valueKg, 62.5);
    expect(data.nutrition.status, TodayModuleStatus.comingSoon);
    expect(data.hydration.status, TodayModuleStatus.empty);
    expect(data.activity.status, TodayModuleStatus.error);
    expect(data.sleep.status, TodayModuleStatus.ready);
    expect(data.nextAction.type, TodayNextActionType.viewPlan);
  });

  test('缺少可选字段和未知扩展字段不会解析失败', () {
    final data = TodayData.fromJson({
      ...response(),
      'futureField': {'anything': true},
      'weight': {'status': 'EMPTY'},
      'tasks': {'status': 'SOMETHING_NEW'},
      'nextAction': {'type': 'FUTURE_ACTION'},
    });

    expect(data.weight.valueKg, isNull);
    expect(data.weight.measuredAt, isNull);
    expect(data.tasks.status, TodayModuleStatus.error);
    expect(data.nextAction.type, TodayNextActionType.unknown);
    expect(data.nextAction.title, '查看今日安排');
  });

  test('本地日期格式不附带时区或时间', () {
    expect(formatLocalDate(DateTime(2026, 9, 8, 23, 59)), '2026-09-08');
  });

  test('解析真实饮食进度', () {
    final json = response();
    json['nutrition'] = {
      'status': 'READY',
      'consumedKcal': 520,
      'targetKcal': 1470,
      'proteinG': 32.5,
      'carbsG': 60,
      'fatG': 15.2,
    };

    final nutrition = TodayData.fromJson(json).nutrition;

    expect(nutrition.consumedKcal, 520);
    expect(nutrition.targetKcal, 1470);
    expect(nutrition.proteinG, 32.5);
  });

  test('解析 Today 运动权威汇总', () {
    final json = response();
    json['activity'] = {
      'status': 'READY',
      'todayDurationMinutes': 30,
      'todayKcal': 180,
      'todayRecordCount': 1,
      'weekExerciseDays': 2,
      'weekDurationMinutes': 75,
      'targetExerciseDays': 4,
      'targetDurationMinutes': 150,
    };

    final activity = TodayData.fromJson(json).activity;
    expect(activity.todayDurationMinutes, 30);
    expect(activity.todayKcal, 180);
    expect(activity.weekExerciseDays, 2);
    expect(activity.targetDurationMinutes, 150);
  });
}
