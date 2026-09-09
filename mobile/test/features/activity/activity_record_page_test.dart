import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/activity/application/activity_controller.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/activity/presentation/activity_record_page.dart';

class _RecordApi extends ApiClient {
  Map<String, dynamic>? body;

  static const running = ActivityType(
    id: 'running',
    name: '跑步',
    category: 'CARDIO',
    scope: ActivityTypeScope.system,
    lowMet: 4,
    mediumMet: 6,
    highMet: 8,
  );

  @override
  Future<List<ActivityType>> getActivityTypes({String query = ''}) async =>
      query.isEmpty || '跑步'.contains(query) ? [running] : [];

  @override
  Future<ActivityType> createCustomActivityType({
    required String name,
    required String referenceTypeId,
  }) async => ActivityType(
    id: 'custom',
    name: name,
    category: 'CARDIO',
    scope: ActivityTypeScope.user,
    lowMet: 4,
    mediumMet: 6,
    highMet: 8,
    referenceTypeId: referenceTypeId,
  );

  @override
  Future<ActivityWriteResult> addActivityRecord(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    body = data;
    return ActivityWriteResult(
      day: ActivityDay.fromJson({
        'date': '2026-09-09',
        'weightKg': 60,
        'records': const [],
      }),
      week: ActivityWeek.fromJson({
        'weekStart': '2026-09-07',
        'weekEnd': '2026-09-13',
        'planStatus': 'NO_PLAN',
      }),
    );
  }
}

Future<(_RecordApi, ActivityController)> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  final api = _RecordApi();
  final controller = ActivityController(
    api,
    userKey: 'u1',
    now: () => DateTime(2026, 9, 9, 10),
  );
  controller.state = ActivityViewState(
    date: DateTime(2026, 9, 9),
    day: ActivityDay.fromJson({
      'date': '2026-09-09',
      'weightKg': 60,
      'records': const [],
    }),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ActivityRecordPage(
        controller: controller,
        selectedDate: DateTime(2026, 9, 9),
        now: () => DateTime(2026, 9, 9, 10),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (api, controller);
}

void main() {
  testWidgets('支持运动、强度、快捷时长和估算热量', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('跑步'));
    await tester.pump();
    expect(find.text('预计消耗：180 kcal（估算值）'), findsOneWidget);

    await tester.tap(find.text('高强度'));
    await tester.tap(find.text('60 分钟'));
    await tester.pump();
    expect(find.text('预计消耗：480 kcal（估算值）'), findsOneWidget);
  });

  testWidgets('校验时长、未来时间和人工热量边界', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('activity-duration')), '0');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.byKey(const Key('activity-save')));
    await tester.pump();
    expect(find.text('请选择运动类型'), findsOneWidget);

    await tester.tap(find.text('跑步'));
    await tester.ensureVisible(find.text('修改消耗热量'));
    await tester.tap(find.text('修改消耗热量'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('activity-calories')), '10001');
    await tester.tap(find.byKey(const Key('activity-save')));
    await tester.pump();
    expect(find.text('运动时长应为 1–1440 分钟'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('activity-duration')), '30');
    await tester.tap(find.byKey(const Key('activity-save')));
    await tester.pump();
    expect(find.text('消耗热量应为 0–10000 kcal'), findsOneWidget);
    await tester.tap(find.text('恢复估算值'));
    await tester.pump();
    expect(find.byKey(const Key('activity-calories')), findsNothing);
  });

  testWidgets('保存提交服务端所需字段', (tester) async {
    final (api, _) = await _pump(tester);
    await tester.tap(find.text('跑步'));
    await tester.tap(find.byKey(const Key('activity-save')));
    await tester.pumpAndSettle();
    expect(api.body?['activityTypeId'], 'running');
    expect(api.body?['intensity'], 'MEDIUM');
    expect(api.body?['durationMinutes'], 30);
    expect(api.body?['finalKcal'], isNull);
  });

  testWidgets('可创建自定义运动并立即选择', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('创建自定义运动'));
    await tester.pumpAndSettle();
    expect(find.text('最相似的内置运动'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '运动名称'), '室内慢跑');
    await tester.tap(find.text('创建并选择'));
    await tester.pumpAndSettle();
    expect(find.text('室内慢跑'), findsOneWidget);
    expect(find.text('预计消耗：180 kcal（估算值）'), findsOneWidget);
  });
}
