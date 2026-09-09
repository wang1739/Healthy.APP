import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/sleep/application/sleep_controller.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';

SleepDay _day(String date, int minutes) => SleepDay.fromJson({
  'date': date,
  'nightDurationMinutes': minutes,
  'records': const [],
});
SleepWeek _week(String date) =>
    SleepWeek.fromJson({'startDate': date, 'endDate': date});

class _Api extends ApiClient {
  bool fail = false;
  final keys = <String>[];
  final loads = <String, Completer<SleepDay>>{};
  int updates = 0;
  @override
  Future<SleepDay> getSleepDay(DateTime date) =>
      loads[formatLocalDate(date)]?.future ??
      Future.value(_day(formatLocalDate(date), 0));
  @override
  Future<SleepWeek> getSleepWeek(DateTime date) async =>
      _week(formatLocalDate(date));
  SleepWriteResult result(Map<String, dynamic> data) =>
      SleepWriteResult(day: _day('2026-09-09', 480), week: _week('2026-09-09'));
  @override
  Future<SleepWriteResult> addSleepRecord(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    if (fail) throw DioException(requestOptions: RequestOptions());
    return result(data);
  }

  @override
  Future<SleepWriteResult> updateSleepRecord(
    String id,
    Map<String, dynamic> data,
  ) async {
    updates++;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return result(data);
  }
}

void main() {
  test('创建失败保留完整草稿且重试复用幂等键', () async {
    final api = _Api()..fail = true;
    final controller = SleepController(
      api,
      userKey: 'u1',
      now: () => DateTime(2026, 9, 9),
      initialDate: DateTime(2026, 9, 9),
    );
    final draft = {
      'recordType': 'NIGHT',
      'startedAt': 'a',
      'endedAt': 'b',
      'qualityScore': 4,
      'tags': ['STRESS'],
      'note': '备注',
    };
    await controller.save(draft);
    expect(controller.state.draft, draft);
    api.fail = false;
    await controller.retrySave();
    expect(api.keys.toSet(), hasLength(1));
    expect(controller.state.draft, isNull);
  });

  test('日期切换不展示旧日且迟到响应不污染当前状态', () async {
    final api = _Api();
    api.loads['2026-09-09'] = Completer<SleepDay>();
    api.loads['2026-09-10'] = Completer<SleepDay>();
    final controller = SleepController(api, userKey: 'u1', now: DateTime.now);
    final first = controller.load(DateTime(2026, 9, 9));
    final second = controller.load(DateTime(2026, 9, 10));
    api.loads['2026-09-10']!.complete(_day('2026-09-10', 300));
    await second;
    api.loads['2026-09-09']!.complete(_day('2026-09-09', 999));
    await first;
    expect(controller.state.day?.nightDurationMinutes, 300);
  });

  test('编辑失败重试仍调用编辑接口且账号日期键隔离', () async {
    final api = _Api()..fail = true;
    final controller = SleepController(
      api,
      userKey: 'u1',
      now: DateTime.now,
      initialDate: DateTime(2026, 9, 9),
    );
    await controller.save({'recordType': 'NAP'}, recordId: 's1');
    api.fail = false;
    await controller.retrySave();
    expect(api.updates, 2);
    expect(
      SleepProviderKey(api, 'a', DateTime(2026, 9, 9)),
      isNot(SleepProviderKey(api, 'b', DateTime(2026, 9, 9))),
    );
  });
}
