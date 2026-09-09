import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/sleep/application/sleep_controller.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:healthy/features/sleep/presentation/sleep_record_page.dart';

class _Api extends ApiClient {
  Map<String, dynamic>? body;
  int calls = 0;
  @override
  Future<SleepWriteResult> addSleepRecord(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    calls++;
    body = data;
    return SleepWriteResult(
      day: SleepDay.fromJson({'date': '2026-09-09', 'records': const []}),
      week: SleepWeek.fromJson({
        'startDate': '2026-09-03',
        'endDate': '2026-09-09',
      }),
    );
  }
}

Future<_Api> _pump(
  WidgetTester tester, {
  SleepRecordType type = SleepRecordType.night,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  final api = _Api();
  final controller = SleepController(
    api,
    userKey: 'u1',
    now: () => DateTime(2026, 9, 9, 8),
    initialDate: DateTime(2026, 9, 9),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: SleepRecordPage(
        controller: controller,
        selectedDate: DateTime(2026, 9, 9),
        initialType: type,
        now: () => DateTime(2026, 9, 9, 8),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('夜间和小睡使用 8 小时与 30 分钟默认草稿', (tester) async {
    await _pump(tester);
    expect(find.text('自动计算时长：8 小时 0 分钟'), findsOneWidget);
    await tester.tap(find.text('午睡/小睡'));
    await tester.pump();
    expect(find.text('自动计算时长：30 分钟'), findsOneWidget);
  });

  testWidgets('提供五级质量、七个标签和默认收起的备注', (tester) async {
    await _pump(tester);
    for (final label in ['很差', '较差', '一般', '良好', '很好']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in sleepTagLabels.values) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const Key('sleep-note')), findsNothing);
    await tester.tap(find.text('添加备注'));
    await tester.pump();
    expect(find.byKey(const Key('sleep-note')), findsOneWidget);
  });

  testWidgets('保存只提交时间区间、质量、标签和备注，不提交时长', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.text('良好'));
    await tester.tap(find.text('压力较大'));
    await tester.tap(find.text('添加备注'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('sleep-note')), '  睡得不错  ');
    tester.testTextInput.hide();
    await tester.tap(find.byKey(const Key('sleep-save')));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(api.body?['qualityScore'], 4);
    expect(api.body?['tags'], ['STRESS']);
    expect(api.body?['note'], '睡得不错');
    expect(api.body?.containsKey('durationMinutes'), isFalse);
  });
}
