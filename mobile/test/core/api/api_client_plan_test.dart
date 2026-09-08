import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'id': 'plan-1', 'status': 'ACTIVE'}),
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
  test('计划接口使用约定路径和载荷', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))
      ..httpClientAdapter = adapter;
    final api = ApiClient(dio: dio);

    await api.previewPlan();
    await api.createPlan(adjustments: {'targetKcal': 1700});
    await api.getCurrentPlan();
    await api.getPlanHistory();
    await api.recalculatePlan('plan-1', expectedVersion: 1);
    await api.updatePlanTargets('plan-1', {
      'targetKcal': 1650,
      'expectedVersion': 1,
    });
    await api.pausePlan('plan-1');
    await api.resumePlan('plan-1');

    expect(
      adapter.requests.map((request) => '${request.method} ${request.path}'),
      [
        'POST /plans/preview',
        'POST /plans',
        'GET /plans/current',
        'GET /plans/history',
        'POST /plans/plan-1/recalculate',
        'PUT /plans/plan-1/targets',
        'POST /plans/plan-1/pause',
        'POST /plans/plan-1/resume',
      ],
    );
    expect(adapter.requests[1].data, {'targetKcal': 1700});
    expect(adapter.requests[4].data, {'expectedVersion': 1});
    expect(adapter.requests[5].data, {
      'targetKcal': 1650,
      'expectedVersion': 1,
    });
  });
}
