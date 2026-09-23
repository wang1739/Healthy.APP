import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/account/presentation/account_detail_pages.dart';
import 'package:healthy/features/report/domain/report_data.dart';

class _AccountRightsApi extends ApiClient {
  List<String>? previewTypes;
  DateTime? previewFrom;
  DateTime? previewTo;
  String? downloadedId;
  int deletionPreviews = 0;
  int deletions = 0;

  @override
  Future<Map<String, dynamic>> getPrivacy() async => {
    'healthAuthorized': true,
    'acceptedPrivacyVersion': '2.0',
    'acceptedHealthVersion': '1.1',
    'latestDocuments': [
      {
        'type': 'HEALTH_DATA_AUTHORIZATION',
        'version': '1.0',
        'effectiveAt': '2026-01-01T00:00:00Z',
        'changeSummary': '旧版',
      },
      {
        'type': 'PRIVACY_POLICY',
        'version': '2.0',
        'effectiveAt': '2026-09-10T00:00:00Z',
        'changeSummary': '最新版',
      },
      {
        'type': 'HEALTH_DATA_AUTHORIZATION',
        'version': '1.1',
        'effectiveAt': '2026-09-10T00:00:00Z',
        'changeSummary': '最新版',
      },
    ],
    'history': [
      {
        'type': 'HEALTH_DATA_AUTHORIZATION',
        'version': '1.1',
        'action': 'ACCEPT',
        'createdAt': '2026-09-11T00:00:00Z',
      },
    ],
  };

  @override
  Future<List<Map<String, dynamic>>> getDataExports() async => [
    {
      'id': 'export-1',
      'status': 'READY',
      'createdAt': '2026-09-22T01:00:00Z',
      'expiresAt': '2099-09-23T01:00:00Z',
    },
    {
      'id': 'export-2',
      'status': 'READY',
      'createdAt': '2026-09-20T01:00:00Z',
      'expiresAt': '2026-09-21T01:00:00Z',
    },
  ];

  @override
  Future<ReportPdf> downloadDataExportPdf(String id) async {
    downloadedId = id;
    return ReportPdf(
      bytes: Uint8List.fromList('%PDF-export'.codeUnits),
      fileName: '轻食记-数据导出.pdf',
    );
  }

  @override
  Future<Map<String, dynamic>> previewHealthDataDeletion(
    List<String> types, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    deletionPreviews++;
    return {
      'recordCounts': {'HYDRATION': 3},
      'affectedReports': 1,
      'affectedPlanVersions': 0,
      'warning': '删除后无法恢复',
    };
  }

  @override
  Future<String?> sendPurposeCode(String phone, String purpose) async =>
      '123456';

  @override
  Future<Map<String, dynamic>> deleteHealthData(
    List<String> types,
    String code, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    deletions++;
    return {'status': '已完成'};
  }
}

void main() {
  test('隐私中心按生效时间选择每类最新文件', () {
    final latest = latestPrivacyDocuments([
      {
        'type': 'HEALTH_DATA_AUTHORIZATION',
        'version': '1.0',
        'effectiveAt': '2026-01-01T00:00:00Z',
      },
      {
        'type': 'HEALTH_DATA_AUTHORIZATION',
        'version': '1.1',
        'effectiveAt': '2026-09-10T00:00:00Z',
      },
    ]);

    expect(latest['HEALTH_DATA_AUTHORIZATION']?['version'], '1.1');
  });

  testWidgets('隐私中心展示当前同意版本和授权历史', (tester) async {
    final api = _AccountRightsApi();
    final session = SessionController(api);
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyCenterPage(api: api, session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已同意版本：1.1'), findsOneWidget);
    expect(find.text('同意与撤回历史'), findsOneWidget);
    expect(find.textContaining('已同意'), findsWidgets);
    expect(find.text('旧版'), findsNothing);
  });

  testWidgets('数据权利页展示真实导出状态并保存可下载 PDF', (tester) async {
    final api = _AccountRightsApi();
    String? savedName;
    await tester.pumpWidget(
      MaterialApp(
        home: DataRightsPage(
          api: api,
          phone: '13800138000',
          session: SessionController(api),
          savePdf: (name, bytes) async {
            savedName = name;
            return 'C:/temp/$name';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('可下载'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.textContaining('24 小时'), findsOneWidget);

    await tester.tap(find.text('下载加密 PDF'));
    await tester.pumpAndSettle();

    expect(api.downloadedId, 'export-1');
    expect(savedName, '轻食记-数据导出.pdf');
    expect(find.textContaining('已保存至'), findsOneWidget);
  });

  testWidgets('健康数据删除先展示服务端影响并要求明确二次确认', (tester) async {
    final api = _AccountRightsApi();
    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DataRightsPage(
          api: api,
          phone: '13800138000',
          session: SessionController(
            api,
            onHealthDataCleared: () async => cleared++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('预览影响并永久删除'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('预览影响并永久删除'));
    await tester.pumpAndSettle();

    expect(find.text('查看删除影响'), findsOneWidget);
    expect(find.textContaining('HYDRATION 3 条'), findsOneWidget);
    await tester.tap(find.text('继续验证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.text('最后确认永久删除'), findsOneWidget);
    expect(api.deletions, 0);
    await tester.tap(find.text('确认永久删除'));
    await tester.pumpAndSettle();

    expect(api.deletionPreviews, 1);
    expect(api.deletions, 1);
    expect(cleared, 1);
  });

  testWidgets('数据权利页在窄屏和大字体下仍可滚动访问', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);
    final api = _AccountRightsApi();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: DataRightsPage(
          api: api,
          phone: '13800138000',
          session: SessionController(api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('导出个人数据'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('预览影响并永久删除'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('预览影响并永久删除'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
