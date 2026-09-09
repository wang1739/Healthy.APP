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
    final body = options.path.endsWith('/auth/sms/login')
        ? {'accessToken': 'a', 'refreshToken': 'r', 'profileComplete': true}
        : options.path.contains('/days/')
        ? {'date': '2026-09-09', 'records': []}
        : options.path.contains('/weeks/')
        ? {'startDate': '2026-09-03', 'endDate': '2026-09-09'}
        : {
            'day': {'date': '2026-09-09', 'records': []},
            'week': {'startDate': '2026-09-03', 'endDate': '2026-09-09'},
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
  test('睡眠日周、新增、编辑和删除使用约定契约', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    final api = ApiClient(
      dio: dio,
      tokenStore: _Store(),
      timezone: () async => 'Asia/Shanghai',
    );
    await api.smsLogin(phone: '1', code: '2', deviceName: 'test');
    await api.getSleepDay(DateTime(2026, 9, 9));
    await api.getSleepWeek(DateTime(2026, 9, 9));
    await api.addSleepRecord({'recordType': 'NIGHT'}, idempotencyKey: 'key-1');
    await api.updateSleepRecord('s1', {'recordType': 'NAP'});
    await api.deleteSleepRecord('s1');
    expect(adapter.calls.skip(1).map((c) => '${c.method} ${c.path}'), [
      'GET /sleep/days/2026-09-09',
      'GET /sleep/weeks/2026-09-09',
      'POST /sleep/records',
      'PUT /sleep/records/s1',
      'DELETE /sleep/records/s1',
    ]);
    expect(adapter.calls[3].headers['Idempotency-Key'], 'key-1');
    expect(adapter.calls[3].data['timezone'], 'Asia/Shanghai');
    expect(adapter.calls[5].queryParameters['timezone'], 'Asia/Shanghai');
  });
}
