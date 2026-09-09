import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/storage/token_store.dart';

class _Store extends TokenStore {
  @override
  Future<void> saveRefreshToken(String token) async {}
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final Object data = options.path.endsWith('/auth/sms/login')
        ? {'accessToken': 'a', 'refreshToken': 'r', 'profileComplete': true}
        : options.path == '/activity/types'
        ? {'items': <Object>[]}
        : options.path.contains('/weeks/')
        ? {
            'weekStart': '2026-09-07',
            'weekEnd': '2026-09-13',
            'exerciseDays': 0,
            'durationMinutes': 0,
            'totalKcal': 0,
            'planStatus': 'NO_PLAN',
          }
        : options.path == '/activity/types/custom'
        ? {
            'id': 'custom',
            'name': '散步机',
            'typeScope': 'USER',
            'lowMet': 2,
            'mediumMet': 3,
            'highMet': 4,
          }
        : {
            'day': {
              'date': '2026-09-09',
              'recordCount': 0,
              'durationMinutes': 0,
              'totalKcal': 0,
              'records': <Object>[],
            },
            'week': {
              'weekStart': '2026-09-07',
              'weekEnd': '2026-09-13',
              'exerciseDays': 0,
              'durationMinutes': 0,
              'totalKcal': 0,
              'planStatus': 'NO_PLAN',
            },
          };
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('运动查询、自定义、新增、编辑和删除契约', () async {
    final adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://x/api/v1'))
      ..httpClientAdapter = adapter;
    final api = ApiClient(
      dio: dio,
      tokenStore: _Store(),
      timezone: () async => 'Asia/Shanghai',
    );
    await api.smsLogin(phone: '1', code: '2', deviceName: 't');
    await api.getActivityTypes(query: '跑');
    expect(adapter.requests.last.queryParameters['query'], '跑');
    await api.createCustomActivityType(name: '散步机', referenceTypeId: 'walking');
    expect(adapter.requests.last.data, {
      'name': '散步机',
      'referenceTypeId': 'walking',
    });
    await api.getActivityDay(DateTime(2026, 9, 9));
    await api.getActivityWeek(DateTime(2026, 9, 9));
    expect(adapter.requests.last.queryParameters['timezone'], 'Asia/Shanghai');
    await api.addActivityRecord({
      'activityTypeId': 'running',
    }, idempotencyKey: 'same-key');
    expect(adapter.requests.last.headers['Idempotency-Key'], 'same-key');
    await api.updateActivityRecord('r1', {'calorieMode': 'ESTIMATED'});
    await api.deleteActivityRecord('r1');

    expect(
      adapter.requests.map((request) => '${request.method} ${request.path}'),
      containsAll([
        'GET /activity/days/2026-09-09',
        'GET /activity/weeks/2026-09-09',
        'POST /activity/records',
        'PUT /activity/records/r1',
        'DELETE /activity/records/r1',
      ]),
    );
  });
}
