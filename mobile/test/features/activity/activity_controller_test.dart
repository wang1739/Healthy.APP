import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/activity/application/activity_controller.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';

ActivityDay _day(String date, int kcal, {double weight = 60}) =>
    ActivityDay.fromJson({
      'date': date,
      'recordCount': kcal == 0 ? 0 : 1,
      'durationMinutes': kcal == 0 ? 0 : 30,
      'totalKcal': kcal,
      'weightKg': weight,
      'records': const [],
    });

ActivityWeek _week(String date) => ActivityWeek.fromJson({
  'weekStart': date,
  'weekEnd': date,
  'exerciseDays': 0,
  'durationMinutes': 0,
  'totalKcal': 0,
  'planStatus': 'NO_PLAN',
});

class _FakeApi extends ApiClient {
  bool fail = false;
  final keys = <String>[];
  final loads = <String, Completer<ActivityDay>>{};
  Map<String, dynamic>? lastBody;

  @override
  Future<ActivityDay> getActivityDay(DateTime date) {
    final key = formatLocalDate(date);
    return loads[key]?.future ?? Future.value(_day(key, 0));
  }

  @override
  Future<ActivityWeek> getActivityWeek(DateTime date) async =>
      _week(formatLocalDate(date));

  @override
  Future<ActivityWriteResult> addActivityRecord(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    lastBody = data;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return ActivityWriteResult(
      day: _day(data['date'] as String, 180),
      week: _week(data['date'] as String),
    );
  }
}

void main() {
  test('预览热量并由服务端写入结果覆盖', () async {
    final api = _FakeApi();
    final controller = ActivityController(
      api,
      userKey: 'u1',
      now: () => DateTime(2026, 9, 9, 9),
    );
    await controller.load(DateTime(2026, 9, 9));
    const type = ActivityType(
      id: 'running',
      name: '跑步',
      category: 'CARDIO',
      scope: ActivityTypeScope.system,
      lowMet: 4,
      mediumMet: 6,
      highMet: 8,
    );
    expect(controller.estimateKcal(type, ActivityIntensity.medium, 30), 180);
    await controller.save({
      'activityTypeId': 'running',
      'intensity': 'MEDIUM',
      'durationMinutes': 30,
      'occurredAt': '2026-09-09T09:00:00+08:00',
    });
    expect(controller.state.day!.totalKcal, 180);
  });

  test('失败保留表单且重试复用幂等键', () async {
    final api = _FakeApi()..fail = true;
    final controller = ActivityController(
      api,
      userKey: 'u1',
      now: () => DateTime(2026, 9, 9, 9),
    );
    await controller.load(DateTime(2026, 9, 9));
    final draft = {
      'activityTypeId': 'running',
      'intensity': 'MEDIUM',
      'durationMinutes': 30,
      'occurredAt': '2026-09-09T09:00:00+08:00',
    };
    await controller.save(draft);
    expect(controller.state.draft, draft);
    api.fail = false;
    await controller.retrySave();
    expect(api.keys.toSet(), hasLength(1));
    expect(controller.state.draft, isNull);
  });

  test('日期切换不展示旧日期且迟到响应不污染当前状态', () async {
    final api = _FakeApi();
    api.loads['2026-09-09'] = Completer<ActivityDay>();
    api.loads['2026-09-10'] = Completer<ActivityDay>();
    final controller = ActivityController(
      api,
      userKey: 'u1',
      now: () => DateTime(2026, 9, 10),
    );
    final first = controller.load(DateTime(2026, 9, 9));
    final second = controller.load(DateTime(2026, 9, 10));
    expect(controller.state.day, isNull);
    api.loads['2026-09-10']!.complete(_day('2026-09-10', 20));
    await second;
    api.loads['2026-09-09']!.complete(_day('2026-09-09', 99));
    await first;
    expect(formatLocalDate(controller.state.date), '2026-09-10');
    expect(controller.state.day!.totalKcal, 20);
  });

  test('缓存按账户和日期键隔离', () {
    final first = ActivityProviderKey(
      _FakeApi(),
      'account-a',
      DateTime(2026, 9, 9),
    );
    final otherAccount = ActivityProviderKey(
      first.api,
      'account-b',
      DateTime(2026, 9, 9),
    );
    final otherDate = ActivityProviderKey(
      first.api,
      'account-a',
      DateTime(2026, 9, 10),
    );
    expect(first, isNot(otherAccount));
    expect(first, isNot(otherDate));
  });
}
