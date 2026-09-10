import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/storage/token_store.dart';

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    if (options.method == 'DELETE') {
      return ResponseBody.fromString('', 204);
    }
    final body = options.path.endsWith('/auth/sms/login')
        ? {'accessToken': 'a', 'refreshToken': 'r', 'profileComplete': true}
        : options.path.contains('/days/')
        ? {'date': '2026-09-10', 'timeline': [], 'allDay': []}
        : options.path.contains('/weeks/')
        ? {'startDate': '2026-09-04', 'endDate': '2026-09-10'}
        : options.path.endsWith('/notifications')
        ? <Object>[]
        : options.path.endsWith('/settings') && options.method == 'GET'
        ? {
            'quietEnabled': true,
            'quietStartTime': '22:30',
            'quietEndTime': '07:00',
            'version': 0,
          }
        : options.path.contains('/instances/')
        ? {
            'id': 'i1',
            'title': '任务',
            'status': 'PENDING',
            'currentLocalDate': '2026-09-10',
          }
        : {
            'instance': {
              'id': 'i1',
              'title': '任务',
              'status': 'PENDING',
              'currentLocalDate': '2026-09-10',
            },
            'day': {'date': '2026-09-10', 'timeline': [], 'allDay': []},
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Store extends TokenStore {
  @override
  Future<void> saveRefreshToken(String token) async {}
}

void main() {
  test('任务读写、状态、删除、设置、事件和计划采用使用书面契约', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    final api = ApiClient(
      dio: dio,
      tokenStore: _Store(),
      timezone: () async => 'Asia/Shanghai',
    );
    await api.smsLogin(phone: '1', code: '2', deviceName: 'test');
    final date = DateTime(2026, 9, 10);
    await api.getTaskDay(date);
    await api.getTaskWeek(date);
    await api.getTaskNotifications(
      from: DateTime(2026, 9, 10),
      to: DateTime(2026, 9, 17),
    );
    await api.createTask({
      'title': '任务',
      'localDate': '2026-09-10',
      'weekdays': [1, 3, 5],
    }, idempotencyKey: 'create-key');
    await api.updateTaskInstance('i1', {
      'title': '今天任务',
      'version': 2,
      'localDate': '2026-09-10',
      'recurrenceType': 'DAILY',
    });
    await api.updateTaskTemplate('t1', {
      'title': '以后任务',
      'version': 2,
      'localDate': '2026-09-10',
      'weekdays': [2, 4],
    });
    await api.completeTask('i1', idempotencyKey: 'complete-key');
    await api.reopenTask('i1', idempotencyKey: 'reopen-key');
    await api.skipTask('i1', idempotencyKey: 'skip-key');
    await api.postponeTask('i1', {
      'mode': 'LATER_30',
    }, idempotencyKey: 'postpone-key');
    await api.deleteTaskInstance('i1');
    await api.deleteTaskTemplate('t1', effectiveDate: date);
    await api.getTaskSettings();
    await api.updateTaskSettings({
      'quietEnabled': true,
      'quietStartTime': '22:30',
      'quietEndTime': '07:00',
      'version': 1,
    });
    await api.reportTaskNotificationEvents([
      {'instanceId': 'i1', 'eventType': 'OPENED'},
    ], idempotencyKey: 'event-key');
    await api.adoptTaskPlanUpdates(date: date, idempotencyKey: 'adopt-key');

    expect(adapter.calls.skip(1).map((c) => '${c.method} ${c.path}'), [
      'GET /tasks/days/2026-09-10',
      'GET /tasks/weeks/2026-09-10',
      'GET /tasks/notifications',
      'POST /tasks',
      'PUT /tasks/instances/i1',
      'PUT /tasks/templates/t1',
      'POST /tasks/instances/i1/complete',
      'POST /tasks/instances/i1/reopen',
      'POST /tasks/instances/i1/skip',
      'POST /tasks/instances/i1/postpone',
      'DELETE /tasks/instances/i1',
      'DELETE /tasks/templates/t1',
      'GET /tasks/settings',
      'PUT /tasks/settings',
      'POST /tasks/notification-events',
      'POST /tasks/plan-updates/adopt',
    ]);
    expect(adapter.calls[1].queryParameters['timezone'], 'Asia/Shanghai');
    expect(adapter.calls[1].path, endsWith('2026-09-10'));
    expect(adapter.calls[4].headers['Idempotency-Key'], 'create-key');
    expect(adapter.calls[7].headers['Idempotency-Key'], 'complete-key');
    expect(adapter.calls[15].headers['Idempotency-Key'], 'event-key');
    expect(adapter.calls[12].queryParameters['effectiveDate'], '2026-09-10');
    expect(adapter.calls[4].data['date'], '2026-09-10');
    expect(adapter.calls[4].data['weekdaysMask'], 21);
    expect(adapter.calls[5].data, {
      'title': '今天任务',
      'expectedVersion': 2,
      'timezone': 'Asia/Shanghai',
    });
    expect(adapter.calls[6].data['effectiveDate'], '2026-09-10');
    expect(adapter.calls[6].data['weekdaysMask'], 10);
    expect(adapter.calls[10].data['type'], 'LATER');
    expect(adapter.calls[14].data['expectedVersion'], 1);
    expect(adapter.calls[16].data['date'], '2026-09-10');
    expect(adapter.calls[16].data['timezone'], 'Asia/Shanghai');
  });

  test('任务接口错误继续使用统一中文错误', () {
    final error = DioException(
      requestOptions: RequestOptions(),
      response: Response(
        requestOptions: RequestOptions(),
        data: {'message': '任务标题不能为空'},
      ),
    );
    expect(ApiClient.errorMessage(error), '任务标题不能为空');
  });
}
