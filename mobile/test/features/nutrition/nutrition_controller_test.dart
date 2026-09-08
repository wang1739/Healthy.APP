import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/nutrition/application/nutrition_controller.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';

NutritionDay day(String date, {int calories = 0}) => NutritionDay.fromJson({
  'date': date,
  'status': calories == 0 ? 'EMPTY' : 'READY',
  'total': {'calories': calories, 'protein': 0, 'carbs': 0, 'fat': 0},
  'target': null,
  'meals': [],
});

class _FakeApi extends ApiClient {
  _FakeApi() : super(dio: Dio());

  int reads = 0;
  int writes = 0;
  bool fail = false;
  Completer<NutritionDay>? pending;
  final keys = <String>[];
  Map<String, dynamic>? updated;

  @override
  Future<NutritionDay> getNutritionDay(DateTime date) async {
    reads++;
    if (pending != null) return pending!.future;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return day(formatLocalDate(date));
  }

  @override
  Future<NutritionDay> addNutritionEntry(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    writes++;
    keys.add(idempotencyKey);
    if (fail) throw DioException(requestOptions: RequestOptions());
    return day(data['date'] as String, calories: 174);
  }

  @override
  Future<NutritionDay> updateNutritionEntry(
    String id,
    Map<String, dynamic> data,
  ) async {
    updated = data;
    return day('2026-09-08', calories: 200);
  }

  @override
  Future<NutritionDay> deleteNutritionEntry(String id) async =>
      day('2026-09-08');
}

void main() {
  test('首次加载、日期缓存和刷新', () async {
    final api = _FakeApi();
    final controller = NutritionController(
      api,
      userKey: 'user-a',
      now: () => DateTime(2026, 9, 8),
    );

    await controller.load(DateTime(2026, 9, 8));
    await controller.load(DateTime(2026, 9, 7));
    await controller.load(DateTime(2026, 9, 8));
    expect(api.reads, 2);
    await controller.refresh();
    expect(api.reads, 3);
  });

  test('未来日期只读且写入使用服务端完整响应', () async {
    final api = _FakeApi();
    final controller = NutritionController(
      api,
      userKey: 'user-a',
      now: () => DateTime(2026, 9, 8),
    );
    await controller.load(DateTime(2026, 9, 9));
    expect(controller.state.futureDate, isTrue);

    await controller.load(DateTime(2026, 9, 8));
    await controller.add({'foodId': 'rice', 'grams': 150});
    expect(controller.state.data?.summary.calories, 174);
    await controller.update('entry-1', {'foodId': 'rice', 'grams': 200});
    expect(api.updated?['date'], '2026-09-08');
  });

  test('重复保存只发送一次，失败保留草稿和页面数据', () async {
    final api = _FakeApi();
    final controller = NutritionController(
      api,
      userKey: 'user-a',
      now: () => DateTime(2026, 9, 8),
    );
    await controller.load(DateTime(2026, 9, 8));
    api.fail = true;
    controller.saveDraft({'foodId': 'rice', 'grams': 150});

    await Future.wait([controller.addDraft(), controller.addDraft()]);

    expect(api.writes, 1);
    expect(controller.state.data, isNotNull);
    expect(controller.state.draft?['grams'], 150);
    expect(controller.state.saveError, isNotNull);

    await controller.addDraft();
    expect(api.keys.toSet(), hasLength(1));
  });

  test('旧日期在途响应不会覆盖当前日期', () async {
    final api = _FakeApi()..pending = Completer<NutritionDay>();
    final controller = NutritionController(
      api,
      userKey: 'user-a',
      now: () => DateTime(2026, 9, 8),
    );
    final old = controller.load(DateTime(2026, 9, 7));
    final pending = api.pending!;
    api.pending = null;
    await controller.load(DateTime(2026, 9, 8));
    pending.complete(day('2026-09-07', calories: 100));
    await old;

    expect(controller.state.date, DateTime(2026, 9, 8));
    expect(controller.state.data?.date, DateTime(2026, 9, 8));
  });

  test('自动释放后不复用上一账户缓存', () async {
    final api = _FakeApi();
    final container = ProviderContainer();
    final key = NutritionProviderKey(api, 'user-a', DateTime(2026, 9, 8));
    final subscription = container.listen(
      nutritionControllerProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    await container
        .read(nutritionControllerProvider(key))
        .load(key.initialDate);
    subscription.close();
    await container.pump();

    final other = NutritionProviderKey(api, 'user-b', DateTime(2026, 9, 8));
    expect(
      container.read(nutritionControllerProvider(other)).state.data,
      isNull,
    );
    container.dispose();
  });
}
