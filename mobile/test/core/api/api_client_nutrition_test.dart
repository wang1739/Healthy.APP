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
    final Object data;
    if (options.path.endsWith('/auth/sms/login')) {
      data = {
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'profileComplete': true,
      };
    } else if (options.path.endsWith('/foods/suggestions')) {
      data = {'recent': [], 'frequent': []};
    } else if (options.path.endsWith('/foods')) {
      data = {'items': []};
    } else if (options.path.contains('/nutrition/')) {
      data = _day;
    } else {
      data = _food;
    }
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

const _food = {
  'id': 'rice',
  'name': '米饭',
  'category': '主食',
  'caloriesPer100g': 116,
  'proteinPer100g': 2.6,
  'carbsPer100g': 25.9,
  'fatPer100g': 0.3,
  'custom': true,
  'portions': [],
};

const _day = {
  'date': '2026-09-08',
  'status': 'EMPTY',
  'total': {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
  'target': null,
  'meals': [],
};

void main() {
  late _Adapter adapter;
  late ApiClient api;

  setUp(() async {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))
      ..httpClientAdapter = adapter;
    api = ApiClient(dio: dio, tokenStore: _MemoryTokenStore());
    await api.smsLogin(
      phone: '13800138000',
      code: '123456',
      deviceName: 'test',
    );
  });

  test('搜索、建议和创建我的食物请求契约', () async {
    await api.searchFoods(query: '米', scope: 'MINE', limit: 8);
    expect(adapter.requests.last.path, '/foods');
    expect(adapter.requests.last.queryParameters, {
      'query': '米',
      'scope': 'MINE',
      'limit': 8,
    });

    await api.getFoodSuggestions(limit: 6);
    expect(adapter.requests.last.path, '/foods/suggestions');

    await api.createCustomFood({
      'name': '自制沙拉',
      'category': 'CUSTOM',
      'baseGrams': 100,
      'calories': 80,
      'protein': 3,
      'carbs': 10,
      'fat': 2,
    });
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.path, '/foods/custom');
    expect((adapter.requests.last.data as Map)['baseGrams'], 100);
  });

  test('读取、新增、编辑和删除饮食请求契约', () async {
    final date = DateTime(2026, 9, 8, 21);
    await api.getNutritionDay(date);
    expect(adapter.requests.last.path, '/nutrition/days/2026-09-08');

    await api.addNutritionEntry({
      'date': '2026-09-08',
      'mealType': 'DINNER',
      'foodId': 'rice',
      'grams': 150,
    }, idempotencyKey: 'stable-key');
    expect(adapter.requests.last.headers['Idempotency-Key'], 'stable-key');
    expect(adapter.requests.last.method, 'POST');

    await api.updateNutritionEntry('entry-1', {'grams': 200});
    expect(adapter.requests.last.path, '/nutrition/entries/entry-1');
    expect(adapter.requests.last.method, 'PUT');

    await api.deleteNutritionEntry('entry-1');
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.headers['Authorization'], 'Bearer access');
  });
}
