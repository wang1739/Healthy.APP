import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/storage/token_store.dart';

class Store extends TokenStore {
  @override
  Future<void> saveRefreshToken(String token) async {}
}

class Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    final data = o.path.endsWith('/auth/sms/login')
        ? {'accessToken': 'a', 'refreshToken': 'r', 'profileComplete': true}
        : o.path.endsWith('/settings')
        ? settings
        : day;
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

const settings = {
  'effectiveTargetMl': 2000,
  'defaultCupMl': 250,
  'reminderEnabled': false,
  'version': 0,
};
const day = {
  'date': '2026-09-08',
  'status': 'EMPTY',
  'consumedMl': 0,
  'targetMl': 2000,
  'remainingMl': 2000,
  'progress': 0,
  'targetSource': 'DEFAULT',
  'settings': settings,
  'entries': [],
};
void main() {
  test('饮水六个请求契约', () async {
    final a = Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://x/api/v1'))
      ..httpClientAdapter = a;
    final api = ApiClient(dio: dio, tokenStore: Store());
    await api.smsLogin(phone: '1', code: '2', deviceName: 't');
    await api.getHydrationDay(DateTime(2026, 9, 8), timezone: 'Asia/Shanghai');
    expect(a.requests.last.queryParameters['timezone'], 'Asia/Shanghai');
    await api.addHydrationEntry({'amountMl': 250}, idempotencyKey: 'same');
    expect(a.requests.last.headers['Idempotency-Key'], 'same');
    await api.deleteHydrationEntry('e', timezone: 'Asia/Shanghai');
    await api.getHydrationSettings();
    await api.updateHydrationSettings(settings);
    await api.adoptPlanHydrationTarget();
    expect(
      a.requests.map((e) => e.path),
      containsAll([
        '/hydration/entries/e',
        '/hydration/settings/adopt-plan-target',
      ]),
    );
  });
}
