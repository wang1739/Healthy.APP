import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/report/domain/report_data.dart';
import 'package:healthy/features/report/presentation/report_sources_page.dart';

class _Api extends ApiClient {
  @override
  Future<List<ReportSource>> getReportSources(
    String id, {
    required String section,
    String? metric,
  }) async => [
    ReportSource.fromJson({
      'sourceType': 'MEAL_ENTRY',
      'resourceId': 'n1',
      'localDate': '2026-09-10',
      'locationLabel': '午餐记录',
    }),
    ReportSource.fromJson({
      'sourceType': 'MEAL_ENTRY',
      'resourceId': 'gone',
      'localDate': '2026-09-09',
      'locationLabel': '旧记录',
      'available': false,
    }),
  ];
}

void main() {
  testWidgets('依据页显示中文定位标签并安全处理已删资源', (tester) async {
    ReportSource? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ReportSourcesPage(
          api: _Api(),
          reportId: 'r1',
          section: 'NUTRITION',
          onOpenSource: (value) => opened = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('午餐记录'), findsOneWidget);
    expect(find.text('原始记录已删除'), findsOneWidget);
    await tester.tap(find.text('午餐记录'));
    expect(opened?.sourceType, 'MEAL_ENTRY');
  });
}
