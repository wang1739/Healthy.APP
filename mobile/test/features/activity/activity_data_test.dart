import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';

void main() {
  test('解析运动类型、记录、日周汇总并忽略扩展字段', () {
    final day = ActivityDay.fromJson({
      'date': '2026-09-09',
      'status': 'READY',
      'recordCount': 1,
      'totalDurationMinutes': 30,
      'totalKcal': 186,
      'weightKg': 62,
      'cacheVersion': 'v1',
      'futureField': true,
      'records': [
        {
          'id': 'r1',
          'activityType': {
            'id': 'running',
            'name': '跑步',
            'category': 'CARDIO',
            'typeScope': 'SYSTEM',
            'lowMet': 4,
            'mediumMet': 6,
            'highMet': 8,
          },
          'activityName': '跑步',
          'intensity': 'MEDIUM',
          'durationMinutes': 30,
          'occurredAt': '2026-09-09T08:00:00+08:00',
          'estimatedKcal': 186,
          'finalKcal': 200,
          'calorieSource': 'USER_OVERRIDE',
          'weightKgSnapshot': 62,
          'metSnapshot': 6,
          'calculationVersion': 'MET_V1',
          'unknown': 'ok',
        },
      ],
    });
    final week = ActivityWeek.fromJson({
      'weekStart': '2026-09-07',
      'weekEnd': '2026-09-13',
      'exerciseDays': 2,
      'durationMinutes': 75,
      'totalKcal': 420,
      'targetExerciseDays': 4,
      'targetDurationMinutes': 150,
      'planStatus': 'ACTIVE',
    });
    final type = ActivityType.fromJson({
      'id': 'running',
      'name': '跑步',
      'category': 'CARDIO',
      'typeScope': 'SYSTEM',
      'lowMet': 4,
      'mediumMet': 6,
      'highMet': 8,
    });

    expect(type.metFor(ActivityIntensity.high), 8);
    expect(day.records.single.activityTypeId, 'running');
    expect(day.records.single.calorieSource, CalorieSource.userOverride);
    expect(day.totalDurationMinutes, 30);
    expect(week.targetDurationMinutes, 150);
    expect(week.planStatus, ActivityPlanStatus.active);
  });

  test('兼容嵌套汇总、未知状态和数字字符串', () {
    final day = ActivityDay.fromJson({
      'date': '2026-09-09',
      'summary': {'recordCount': '2', 'durationMinutes': '45', 'kcal': '220'},
      'records': const [],
    });
    final week = ActivityWeek.fromJson({
      'startDate': '2026-09-07',
      'endDate': '2026-09-13',
      'summary': {'days': '1', 'minutes': '30', 'kcal': '100'},
      'planStatus': 'NEW_SERVER_STATE',
    });

    expect(day.recordCount, 2);
    expect(day.totalKcal, 220);
    expect(week.exerciseDays, 1);
    expect(week.planStatus, ActivityPlanStatus.unknown);
  });
}
