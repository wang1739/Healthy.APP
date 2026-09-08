import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/today/application/today_controller.dart';
import 'package:healthy/features/today/domain/today_data.dart';

TodayData data(DateTime date) => TodayData.fromJson({
  'date': formatLocalDate(date),
  'plan': {'status': 'EMPTY', 'state': 'EMPTY'},
  'weight': {'status': 'EMPTY'},
  'nutrition': {'status': 'COMING_SOON'},
  'hydration': {'status': 'COMING_SOON'},
  'activity': {'status': 'COMING_SOON'},
  'sleep': {'status': 'COMING_SOON'},
  'tasks': {'status': 'COMING_SOON'},
  'nextAction': {'type': 'CREATE_PLAN', 'title': '生成减脂计划'},
});

class _FakeApi extends ApiClient {
  _FakeApi() : super(dio: Dio());

  int calls = 0;
  bool fail = false;
  Completer<TodayData>? pending;
  final dates = <DateTime>[];

  @override
  Future<TodayData> getToday(DateTime date) async {
    calls++;
    dates.add(date);
    if (pending != null) return pending!.future;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return data(date);
  }
}

void main() {
  test('首次加载和下拉刷新成功', () async {
    final api = _FakeApi();
    final controller = TodayController(api);

    await controller.load(DateTime(2026, 9, 8));
    await controller.refresh();

    expect(api.calls, 2);
    expect(controller.state.data?.date, DateTime(2026, 9, 8));
    expect(controller.state.loading, isFalse);
    expect(controller.state.stale, isFalse);
  });

  test('刷新失败保留上次成功数据并标记可能不是最新', () async {
    final api = _FakeApi();
    final controller = TodayController(api);
    await controller.load(DateTime(2026, 9, 8));
    api.fail = true;

    await controller.refresh();

    expect(controller.state.data, isNotNull);
    expect(controller.state.stale, isTrue);
    expect(controller.state.error, '刷新失败，当前内容可能不是最新');
  });

  test('首次失败显示完整错误状态', () async {
    final api = _FakeApi()..fail = true;
    final controller = TodayController(api);

    await controller.load(DateTime(2026, 9, 8));

    expect(controller.state.data, isNull);
    expect(controller.state.error, '网络连接失败，请稍后重试');
  });

  test('日期变化后请求新日期', () async {
    final api = _FakeApi();
    final controller = TodayController(api);
    await controller.load(DateTime(2026, 9, 8));

    await controller.load(DateTime(2026, 9, 9));

    expect(api.dates, [DateTime(2026, 9, 8), DateTime(2026, 9, 9)]);
    expect(controller.state.data?.date, DateTime(2026, 9, 9));
  });

  test('并发加载只发出一次请求', () async {
    final api = _FakeApi()..pending = Completer<TodayData>();
    final controller = TodayController(api);

    final first = controller.load(DateTime(2026, 9, 8));
    final second = controller.load(DateTime(2026, 9, 8));
    expect(api.calls, 1);
    api.pending!.complete(data(DateTime(2026, 9, 8)));
    await Future.wait([first, second]);

    expect(api.calls, 1);
  });

  test('加载中跨日会在当前请求完成后加载新日期', () async {
    final api = _FakeApi()..pending = Completer<TodayData>();
    final controller = TodayController(api);
    final first = controller.load(DateTime(2026, 9, 8));
    final second = controller.load(DateTime(2026, 9, 9));
    final pending = api.pending!;
    api.pending = null;
    pending.complete(data(DateTime(2026, 9, 8)));
    await first;
    await second;

    expect(api.calls, 2);
    expect(controller.state.data?.date, DateTime(2026, 9, 9));
  });
}
