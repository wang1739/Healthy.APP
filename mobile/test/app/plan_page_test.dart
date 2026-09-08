import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/plan/application/plan_controller.dart';
import 'package:healthy/features/plan/presentation/plan_page.dart';

Map<String, dynamic> _plan({
  String status = 'ACTIVE',
  bool needsRecalculation = false,
}) {
  final result = {
    'ruleVersion': 'FAT_LOSS_V1',
    'targetKcal': 1700,
    'expectedWeeklyChangeKg': 0.45,
    'proteinG': 106,
    'carbsG': 213,
    'fatG': 47,
    'waterMl': 2100,
    'exerciseDays': 3,
    'exerciseMinutes': 150,
    'sleepHours': 8.0,
    'bmi': 24.2,
    'bmrKcal': 1450,
    'tdeeKcal': 2100,
    'suggestedTargetDate': '2027-01-08',
  };
  if (status == 'PREVIEW') return {...result, 'status': status};
  return {
    'state': needsRecalculation ? 'NEEDS_RECALCULATION' : status,
    'planId': 'plan-1',
    'needsRecalculation': needsRecalculation,
    'currentWeek': 2,
    'currentVersion': 1,
    'pausedAt': status == 'PAUSED' ? '2026-09-08T10:00:00' : null,
    'plan': result,
  };
}

class _FakePlanApi extends ApiClient {
  _FakePlanApi(this.current, {this.preview, this.previewErrorCode})
    : super(dio: Dio());

  Map<String, dynamic> current;
  Map<String, dynamic>? preview;
  String? previewErrorCode;
  bool fail = false;
  int confirmed = 0;
  int recalculated = 0;
  int paused = 0;
  int resumed = 0;

  @override
  Future<Map<String, dynamic>> getCurrentPlan() async {
    if (fail) throw DioException(requestOptions: RequestOptions());
    return current;
  }

  @override
  Future<Map<String, dynamic>> previewPlan() async {
    if (previewErrorCode != null) {
      final request = RequestOptions();
      throw DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 422,
          data: {'code': previewErrorCode, 'message': '当前目标的个性计划尚未开放'},
        ),
      );
    }
    return preview ?? _plan(status: 'PREVIEW');
  }

  @override
  Future<Map<String, dynamic>> createPlan({
    Map<String, dynamic>? adjustments,
  }) async {
    confirmed++;
    return current = _plan();
  }

  @override
  Future<Map<String, dynamic>> recalculatePlan(
    String id, {
    required int expectedVersion,
  }) async {
    recalculated++;
    return current = _plan();
  }

  @override
  Future<Map<String, dynamic>> pausePlan(String id) async {
    paused++;
    return current = _plan(status: 'PAUSED');
  }

  @override
  Future<Map<String, dynamic>> resumePlan(String id) async {
    resumed++;
    return current = _plan();
  }

  @override
  Future<Map<String, dynamic>> updatePlanTargets(
    String id,
    Map<String, dynamic> targets,
  ) async => current = {...current, ...targets};
}

Future<void> _pump(
  WidgetTester tester,
  _FakePlanApi api, {
  bool autoPreview = false,
  VoidCallback? onConfirmed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlanPage(
            key: ValueKey(api),
            api: api,
            access: UserAccess.profileComplete,
            riskBlocked: false,
            autoPreview: autoPreview,
            onProtectedAction: (_) {},
            onConfirmed: onConfirmed ?? () {},
            onEditProfile: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  final target = find.text(label).last;
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  test('10 kcal 生成值的调整区间仍保持 50 kcal 步长', () {
    final data = PlanData.fromJson({
      ..._plan(status: 'PREVIEW'),
      'targetKcal': 1470,
      'tdeeKcal': 1843,
    });

    expect(data.minimumTargetKcal, 1470);
    expect(data.maximumTargetKcal, 1820);
    expect(data.maximumTargetKcal - data.minimumTargetKcal, 350);
  });

  testWidgets('无计划时提供生成入口', (tester) async {
    await _pump(tester, _FakePlanApi({'status': 'EMPTY'}));
    expect(find.text('还没有减脂计划'), findsOneWidget);
    expect(find.text('生成减脂计划'), findsOneWidget);
  });

  testWidgets('档案完成后自动进入摘要优先的预览', (tester) async {
    await _pump(
      tester,
      _FakePlanApi({'status': 'EMPTY'}, preview: _plan(status: 'PREVIEW')),
      autoPreview: true,
    );
    expect(find.text('计划预览'), findsOneWidget);
    expect(find.text('1700'), findsOneWidget);
    expect(find.text('确认采用计划'), findsOneWidget);
    expect(find.text('为什么这样安排'), findsOneWidget);
  });

  testWidgets('执行状态提供暂停操作', (tester) async {
    await _pump(tester, _FakePlanApi(_plan()));
    expect(find.text('执行中'), findsOneWidget);
    expect(find.text('暂停计划'), findsOneWidget);
  });

  testWidgets('待重算状态提供重新计算操作', (tester) async {
    await _pump(tester, _FakePlanApi(_plan(needsRecalculation: true)));
    expect(find.text('需要重新计算'), findsOneWidget);
    expect(find.text('重新计算'), findsOneWidget);
  });

  testWidgets('暂停状态提供恢复操作', (tester) async {
    await _pump(tester, _FakePlanApi(_plan(status: 'PAUSED')));
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('恢复计划'), findsOneWidget);
  });

  testWidgets('风险状态不展示普通减脂数值', (tester) async {
    await _pump(
      tester,
      _FakePlanApi({'status': 'RISK_BLOCKED', 'message': '当前情况不适合生成普通减脂计划'}),
    );
    expect(find.text('暂不生成普通减脂计划'), findsOneWidget);
    expect(find.text('返回修改档案'), findsOneWidget);
    expect(find.text('1700'), findsNothing);
  });

  testWidgets('非减脂目标显示尚未开放', (tester) async {
    await _pump(
      tester,
      _FakePlanApi({
        'state': 'EMPTY',
      }, previewErrorCode: 'PLAN_GOAL_UNSUPPORTED'),
      autoPreview: true,
    );
    expect(find.text('当前目标计划尚未开放'), findsOneWidget);
    expect(find.text('修改健康目标'), findsOneWidget);
  });

  testWidgets('网络失败保留缓存并允许重试', (tester) async {
    final api = _FakePlanApi(_plan());
    await _pump(tester, api);
    api.fail = true;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂时无法更新'), findsOneWidget);
    expect(find.text('1700'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('确认、重算、暂停和恢复调用计划接口', (tester) async {
    final previewApi = _FakePlanApi(_plan(status: 'PREVIEW'));
    var enteredToday = false;
    await _pump(tester, previewApi, onConfirmed: () => enteredToday = true);
    await _tapVisible(tester, '确认采用计划');
    expect(previewApi.confirmed, 1);
    expect(enteredToday, isTrue);

    final recalculateApi = _FakePlanApi(_plan(needsRecalculation: true));
    await _pump(tester, recalculateApi);
    await _tapVisible(tester, '重新计算');
    expect(recalculateApi.recalculated, 1);

    final pauseApi = _FakePlanApi(_plan());
    await _pump(tester, pauseApi);
    await _tapVisible(tester, '暂停计划');
    await tester.tap(find.text('确认暂停'));
    await tester.pumpAndSettle();
    expect(pauseApi.paused, 1);

    final resumeApi = _FakePlanApi(_plan(status: 'PAUSED'));
    await _pump(tester, resumeApi);
    await _tapVisible(tester, '恢复计划');
    expect(resumeApi.resumed, 1);
  });
}
