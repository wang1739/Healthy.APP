import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/report/domain/report_data.dart';
import 'package:healthy/features/report/presentation/report_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthReport _value() => HealthReport.fromJson({
  'id': 'r1',
  'type': 'WEEKLY',
  'periodStart': '2026-09-07',
  'periodEnd': '2026-09-13',
  'periodStatus': 'IN_PROGRESS',
  'version': 2,
  'dataCutoffAt': '2026-09-10T02:00:00Z',
  'conclusion': '本周记录已形成可查看的阶段总结',
  'sufficientSectionCount': 4,
  'sourceDataChanged': true,
  'keyMetrics': [
    {'code': 'DAYS', 'label': '充分栏目', 'value': '4', 'unit': '个'},
  ],
  'attentionItems': ['睡眠记录还可以更完整'],
  'sections': [
    for (final item in const [
      ('体重与计划', 'WEIGHT_PLAN'),
      ('饮食', 'NUTRITION'),
      ('饮水', 'HYDRATION'),
      ('运动', 'ACTIVITY'),
      ('睡眠', 'SLEEP'),
      ('每日任务', 'TASKS'),
    ])
      {
        'title': item.$1,
        'code': item.$2,
        'sufficiency': 'SUFFICIENT',
        'sufficiencyReason': '数据充分',
        'metrics': [
          {
            'code': 'COUNT',
            'label': '记录',
            'value': '3',
            'unit': '次',
            'targetComparison': '与目标相差 1 次',
            'previousComparison': '与上一周持平',
          },
        ],
      },
  ],
  'recommendations': [
    {'code': 'KEEP', 'title': '保持记录', 'description': '继续记录会让下次报告更准确'},
  ],
});

class _Api extends ApiClient {
  int loads = 0;
  @override
  Future<ReportPageData> getReports({
    required ReportType type,
    required DateTime date,
  }) async {
    loads++;
    return ReportPageData(items: [ReportSummary.fromJson(_value().toJson())]);
  }

  @override
  Future<HealthReport> getReport(String id) async => _value();
  @override
  Future<HealthReport> generateReport({
    required ReportType type,
    required DateTime date,
    required String idempotencyKey,
  }) async => _value();
  @override
  Future<List<ReportSource>> getReportSources(
    String id, {
    required String section,
    String? metric,
  }) async => [
    ReportSource.fromJson({
      'sourceType': 'NUTRITION',
      'sourceId': 'n1',
      'sourceLocalDate': '2026-09-10',
      'label': '午餐记录',
    }),
  ];
}

Widget _app(
  _Api api,
  UserAccess access, {
  Size size = const Size(390, 844),
  double scale = 1,
}) => ProviderScope(
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: ReportPage(
        api: api,
        access: access,
        accountKey: 'a',
        onProtectedAction: (_) {},
        onOpenSource: (_) {},
        now: () => DateTime(2026, 9, 10),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('游客显示中文示例且不请求私人数据', (tester) async {
    final api = _Api();
    await tester.pumpWidget(_app(api, UserAccess.guest));
    expect(find.text('健康报告示例'), findsOneWidget);
    expect(find.text('下载示例报告'), findsOneWidget);
    expect(find.text('查看历史版本'), findsOneWidget);
    expect(find.text('查看示例依据'), findsOneWidget);
    await tester.tap(find.text('月报'));
    await tester.pump();
    expect(find.text('这是月报示例'), findsOneWidget);
    expect(api.loads, 0);
  });
  testWidgets('未建档显示建档引导且不显示私人报告', (tester) async {
    final api = _Api();
    await tester.pumpWidget(_app(api, UserAccess.profileIncomplete));
    expect(find.text('先完成健康档案'), findsOneWidget);
    expect(api.loads, 0);
  });
  testWidgets('结论优先展示关键数字、关注项和六个栏目', (tester) async {
    await tester.pumpWidget(_app(_Api(), UserAccess.profileComplete));
    await tester.pumpAndSettle();
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('需要关注'), findsOneWidget);
    expect(find.text('数据已更新，可重新生成'), findsOneWidget);
    for (final title in const ['体重与计划', '饮食', '饮水', '运动', '睡眠', '每日任务']) {
      await tester.scrollUntilVisible(
        find.text(title),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title), findsOneWidget);
    }
  });
  testWidgets('360px 与 2.0x 字体可滚动且无溢出', (tester) async {
    await tester.pumpWidget(
      _app(
        _Api(),
        UserAccess.profileComplete,
        size: const Size(360, 720),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
