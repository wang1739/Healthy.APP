import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/storage/token_store.dart';
import 'package:healthy/features/report/domain/report_data.dart';

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    if (options.path.endsWith('/pdf')) {
      return ResponseBody.fromBytes(
        Uint8List.fromList('%PDF-test'.codeUnits),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/pdf'],
          'content-disposition': [
            "attachment; filename=health-report.pdf; filename*=UTF-8''%E5%81%A5%E5%BA%B7%E5%91%A8%E6%8A%A5.pdf",
          ],
        },
      );
    }
    if (options.method == 'DELETE') return ResponseBody.fromString('', 204);
    final Object body = options.path.endsWith('/auth/sms/login')
        ? {'accessToken': 'a', 'refreshToken': 'r', 'profileComplete': true}
        : options.path.endsWith('/sources')
        ? {
            'items': [
              {
                'sourceType': 'NUTRITION',
                'sourceId': 'n1',
                'sourceLocalDate': '2026-09-10',
                'label': '午餐记录',
              },
            ],
          }
        : options.method == 'GET' && options.path == '/reports'
        ? {'items': <Object>[], 'page': 0, 'totalPages': 1}
        : {
            'id': 'r1',
            'type': 'DAILY',
            'periodStart': '2026-09-10',
            'periodEnd': '2026-09-10',
            'periodStatus': 'IN_PROGRESS',
            'version': 1,
            'sections': <Object>[],
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
  test('报告生成、列表、详情、依据、PDF 与删除使用确认契约', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    final api = ApiClient(
      dio: dio,
      tokenStore: _Store(),
      timezone: () async => 'Asia/Shanghai',
    );
    await api.smsLogin(phone: '1', code: '2', deviceName: 'test');
    final date = DateTime(2026, 9, 10);

    await api.generateReport(
      type: ReportType.daily,
      date: date,
      idempotencyKey: 'report-key',
    );
    await api.getReports(type: ReportType.weekly, date: date);
    await api.getReport('r1');
    await api.getReportSources('r1', section: 'NUTRITION', metric: 'CALORIES');
    final pdf = await api.downloadReportPdf('r1');
    await api.deleteReport('r1');

    expect(adapter.calls.skip(1).map((e) => '${e.method} ${e.path}'), [
      'POST /reports',
      'GET /reports',
      'GET /reports/r1',
      'GET /reports/r1/sources',
      'GET /reports/r1/pdf',
      'DELETE /reports/r1',
    ]);
    expect(adapter.calls[1].headers['Idempotency-Key'], 'report-key');
    expect(adapter.calls[1].data, {
      'type': 'DAILY',
      'date': '2026-09-10',
      'timezone': 'Asia/Shanghai',
    });
    expect(adapter.calls[2].queryParameters, {
      'type': 'WEEKLY',
      'date': '2026-09-10',
      'timezone': 'Asia/Shanghai',
    });
    expect(adapter.calls[4].queryParameters, {
      'section': 'NUTRITION',
      'metric': 'CALORIES',
    });
    expect(String.fromCharCodes(pdf.bytes), startsWith('%PDF'));
    expect(pdf.fileName, '健康周报.pdf');
  });
}
