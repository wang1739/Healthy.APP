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
    final body = options.path.endsWith('/measurements')
        ? <Object?>[]
        : <String, Object?>{'sections': <String, Object?>{}};
    return ResponseBody.fromString(
      jsonEncode(body),
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
  test('档案分区接口使用约定路径并只提交当前分区', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))
      ..httpClientAdapter = adapter;
    final api = ApiClient(dio: dio);

    await api.getProfileSections();
    await api.saveProfileSection('lifestyle', {
      'workStyle': 'ACTIVE',
      'sleepHours': 8,
    }, expectedVersion: 4);
    await api.getProfileMeasurements();
    await api.saveProfileSection('basic', {
      'birthDate': '1990-01-01',
    }, expectedVersion: 5);
    await api.saveProfileSection('body', {'heightCm': 178}, expectedVersion: 6);
    await api.saveProfileSection('goal', {
      'goalType': 'FAT_LOSS',
    }, expectedVersion: 7);
    await api.saveProfileSection('preferences', {
      'dietType': 'BALANCED',
    }, expectedVersion: 8);
    await api.saveProfileSection('risk', {
      'pregnant': false,
      'breastfeeding': false,
      'eatingDisorderRisk': false,
      'seriousChronicDisease': false,
      'unsafeTarget': false,
    }, expectedVersion: 9);

    expect(
      adapter.requests.map((request) => '${request.method} ${request.path}'),
      [
        'GET /profile/sections',
        'PUT /profile/sections/lifestyle',
        'GET /profile/measurements',
        'PUT /profile/sections/basic-info',
        'PUT /profile/sections/body-data',
        'PUT /profile/sections/health-goal',
        'PUT /profile/sections/dietary-preferences',
        'PUT /profile/sections/risk-info',
      ],
    );
    expect(adapter.requests[1].data, {
      'workStyle': 'ACTIVE',
      'sleepHours': 8,
      'expectedVersion': 4,
    });
    expect(adapter.requests.last.data, {
      'pregnant': false,
      'breastfeeding': false,
      'eatingDisorderRisk': false,
      'seriousChronicDisease': false,
      'unsafeTarget': false,
      'expectedVersion': 9,
    });
  });
}
