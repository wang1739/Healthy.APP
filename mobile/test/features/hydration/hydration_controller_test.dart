import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/hydration/application/hydration_controller.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';

HydrationDay day(int consumed) => HydrationDay.fromJson({
  'date': '2026-09-08',
  'status': 'READY',
  'consumedMl': consumed,
  'targetMl': 2000,
  'remainingMl': 2000 - consumed,
  'progress': consumed / 2000,
  'targetSource': 'DEFAULT',
  'settings': {
    'defaultCupMl': 250,
    'effectiveTargetMl': 2000,
    'reminderEnabled': false,
    'version': 0,
  },
  'entries': [],
});

class Fake extends ApiClient {
  bool fail = false;
  final keys = <String>[];
  Map<String, dynamic>? requestData;
  @override
  Future<HydrationDay> getHydrationDay(
    DateTime d, {
    required String timezone,
  }) async => day(0);
  @override
  Future<HydrationDay> addHydrationEntry(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    requestData = data;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return day(data['amountMl'] as int);
  }
}

void main() {
  test('预计进度失败撤回且重试复用幂等键', () async {
    final api = Fake();
    final c = HydrationController(
      api,
      userKey: 'u',
      now: () => DateTime(2026, 9, 8),
      timezone: () => Future.value('Asia/Shanghai'),
    );
    await c.load(DateTime(2026, 9, 8));
    api.fail = true;
    await c.add(250);
    expect(c.state.data!.consumedMl, 0);
    expect(c.state.retryAmountMl, 250);
    api.fail = false;
    await c.retry();
    expect(c.state.data!.consumedMl, 250);
    expect(api.keys.toSet(), hasLength(1));
  });

  test('通知调度失败不影响服务端权威写入', () async {
    final api = Fake();
    final c = HydrationController(
      api,
      userKey: 'u',
      now: () => DateTime(2026, 9, 8),
      timezone: () => Future.value('Asia/Shanghai'),
      syncReminders: (_) async => throw StateError('notifications unavailable'),
    );
    await c.load(DateTime(2026, 9, 8));
    await c.add(250);
    expect(c.state.data!.consumedMl, 250);
    expect(c.state.saveError, isNull);
  });

  test('提交后端可解析的带时区饮水时间', () async {
    final api = Fake();
    final c = HydrationController(
      api,
      userKey: 'u',
      now: () => DateTime(2026, 9, 8, 9, 30),
      timezone: () => Future.value('Asia/Shanghai'),
    );
    await c.load(DateTime(2026, 9, 8));
    await c.add(250);
    final occurredAt = api.requestData!['occurredAt'] as String;
    expect(occurredAt, endsWith('Z'));
    expect(DateTime.parse(occurredAt).isUtc, isTrue);
  });
}
