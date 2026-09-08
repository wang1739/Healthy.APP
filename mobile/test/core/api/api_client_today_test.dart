import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/storage/token_store.dart';

class _MemoryTokenStore extends TokenStore {
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
    final data = options.path.endsWith('/auth/sms/login')
        ? {
            'accessToken': 'access',
            'refreshToken': 'refresh',
            'profileComplete': true,
          }
        : {
            'date': '2026-09-08',
            'plan': {'status': 'EMPTY', 'state': 'EMPTY'},
            'weight': {'status': 'EMPTY'},
            'nutrition': {'status': 'COMING_SOON'},
            'hydration': {'status': 'COMING_SOON'},
            'activity': {'status': 'COMING_SOON'},
            'sleep': {'status': 'COMING_SOON'},
            'tasks': {'status': 'COMING_SOON'},
            'nextAction': {'type': 'CREATE_PLAN', 'title': '生成减脂计划'},
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
  test('getToday 使用本地日期查询参数和鉴权头', () async {
    final adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))
      ..httpClientAdapter = adapter;
    final api = ApiClient(dio: dio, tokenStore: _MemoryTokenStore());
    await api.smsLogin(
      phone: '13800138000',
      code: '123456',
      deviceName: 'test',
    );

    final data = await api.getToday(DateTime(2026, 9, 8, 22, 30));

    final request = adapter.requests.last;
    expect(request.method, 'GET');
    expect(request.path, '/today');
    expect(request.queryParameters, {'date': '2026-09-08'});
    expect(request.headers['Authorization'], 'Bearer access');
    expect(data.date, DateTime(2026, 9, 8));
  });
}
