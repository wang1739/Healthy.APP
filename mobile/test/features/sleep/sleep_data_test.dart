import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';

void main() {
  test('解析睡眠记录、质量、标签、日汇总和七天统计', () {
    final day = SleepDay.fromJson({
      'date': '2026-09-09',
      'status': 'READY',
      'nightDurationMinutes': 450,
      'napDurationMinutes': 30,
      'targetMinutes': 480,
      'planState': 'ACTIVE',
      'records': [
        {
          'id': 's1',
          'recordType': 'NIGHT',
          'startedAt': '2026-09-08T15:30:00Z',
          'endedAt': '2026-09-08T23:00:00Z',
          'wakeLocalDate': '2026-09-09',
          'durationMinutes': 450,
          'qualityScore': 4,
          'tags': [
            'STRESS',
            {'tagCode': 'SCREEN_TIME'},
          ],
          'note': '睡得不错',
          'futureField': true,
        },
      ],
    });
    final week = SleepWeek.fromJson({
      'startDate': '2026-09-03',
      'endDate': '2026-09-09',
      'averageNightDurationMinutes': 430,
      'targetMetDays': 3,
      'averageQuality': 3.5,
      'napDurationMinutes': 60,
      'hasEnoughTrendData': true,
      'planState': 'ACTIVE',
      'days': [
        {
          'date': '2026-09-09',
          'nightDurationMinutes': 450,
          'napDurationMinutes': 30,
        },
      ],
    });
    expect(day.night?.durationMinutes, 450);
    expect(day.night?.tags, ['STRESS', 'SCREEN_TIME']);
    expect(sleepQualityLabel(day.night?.qualityScore), '良好');
    expect(week.averageQuality, 3.5);
    expect(week.targetAchievedDays, 3);
    expect(week.napTotalMinutes, 60);
    expect(week.planStatus, SleepPlanStatus.active);
    expect(week.dailyPoints.single.nightMinutes, 450);
  });

  test('未知计划状态和缺失可选字段安全降级', () {
    final day = SleepDay.fromJson({'date': '2026-09-09', 'records': const []});
    final week = SleepWeek.fromJson({
      'startDate': '2026-09-03',
      'endDate': '2026-09-09',
      'status': 'FUTURE',
    });
    expect(day.status, 'EMPTY');
    expect(day.targetMinutes, isNull);
    expect(week.planStatus, SleepPlanStatus.unknown);
    expect(week.averageQuality, isNull);
  });
}
