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
    if (options.path.endsWith('/download')) {
      return ResponseBody.fromBytes(
        Uint8List.fromList('%PDF-export'.codeUnits),
        200,
        headers: {
          'content-disposition': [
            "attachment; filename*=UTF-8''%E8%BD%BB%E9%A3%9F%E8%AE%B0-%E6%95%B0%E6%8D%AE%E5%AF%BC%E5%87%BA.pdf",
          ],
        },
      );
    }
    final body = options.path.endsWith('/auth/sms/login')
        ? {'accessToken': 'a', 'refreshToken': 'r', 'profileComplete': true}
        : <String, Object?>{};
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
  test('数据删除传递类型和日期范围，导出下载使用确认契约', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    final api = ApiClient(
      dio: dio,
      tokenStore: _Store(),
      timezone: () async => 'Asia/Shanghai',
    );
    await api.smsLogin(phone: '1', code: '2', deviceName: 'test');
    final from = DateTime(2026, 9, 1);
    final to = DateTime(2026, 9, 20);

    await api.previewHealthDataDeletion(
      ['HYDRATION', 'SLEEP'],
      fromDate: from,
      toDate: to,
    );
    await api.deleteHealthData(
      ['HYDRATION', 'SLEEP'],
      '123456',
      fromDate: from,
      toDate: to,
    );
    final pdf = await api.downloadDataExportPdf('export-1');

    expect(adapter.calls[1].data, {
      'dataTypes': ['HYDRATION', 'SLEEP'],
      'fromDate': '2026-09-01',
      'toDate': '2026-09-20',
    });
    expect(adapter.calls[2].data, {
      'dataTypes': ['HYDRATION', 'SLEEP'],
      'fromDate': '2026-09-01',
      'toDate': '2026-09-20',
      'code': '123456',
    });
    expect(adapter.calls[3].path, '/data-exports/export-1/download');
    expect(pdf.fileName, '轻食记-数据导出.pdf');
  });
}
