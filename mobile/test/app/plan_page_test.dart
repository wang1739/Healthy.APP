import 'dart:async';

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
  _FakePlanApi(
    this.current, {
    this.preview,
    this.previewErrorCode,
    this.recalculationErrorCode,
  }) : super(dio: Dio());

  Map<String, dynamic> current;
  Map<String, dynamic>? preview;
  String? previewErrorCode;
  String? recalculationErrorCode;
  bool fail = false;
  int confirmed = 0;
  int previewed = 0;
  int recalculated = 0;
  int paused = 0;
  int resumed = 0;
  int profileReads = 0;
  int currentReads = 0;
  int? confirmedExpectedVersion;
  String? confirmedPreviewId;
  Map<String, dynamic>? confirmedAdjustments;
  bool confirmConflict = false;
  Completer<List<Map<String, dynamic>>>? historyResult;

  @override
  Future<Map<String, dynamic>> getCurrentPlan() async {
    currentReads++;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return current;
  }

  @override
  Future<Map<String, dynamic>> previewPlan() async {
    previewed++;
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
    confirmedAdjustments = adjustments == null
        ? null
        : Map<String, dynamic>.from(adjustments);
    return current = _plan();
  }

  @override
  Future<Map<String, dynamic>> recalculatePlan(
    String id, {
    required int expectedVersion,
  }) async {
    previewed++;
    if (recalculationErrorCode != null) {
      final request = RequestOptions();
      throw DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 422,
          data: {
            'code': recalculationErrorCode,
            'message': recalculationErrorCode == 'PLAN_RISK_BLOCKED'
                ? '当前健康风险不适合生成普通减脂计划'
                : '当前目标的个性计划尚未开放',
          },
        ),
      );
    }
    return {
      'state': 'RECALCULATION_PREVIEW',
      'planId': id,
      'baseVersion': expectedVersion,
      'previewVersion': expectedVersion + 1,
      'profileVersion': 12,
      'previewId': 'preview-1',
      'plan': preview ?? _plan(status: 'PREVIEW'),
    };
  }

  @override
  Future<Map<String, dynamic>> confirmPlanRecalculation(
    String id, {
    required int expectedVersion,
    required String previewId,
  }) async {
    recalculated++;
    confirmedExpectedVersion = expectedVersion;
    confirmedPreviewId = previewId;
    if (confirmConflict) {
      current = _plan(status: 'PAUSED');
      final request = RequestOptions();
      throw DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {
            'code': 'PLAN_PREVIEW_CONFLICT',
            'message': '健康档案已更新，请重新生成计划预览',
          },
        ),
      );
    }
    return current = _plan();
  }

  @override
  Future<Map<String, dynamic>> getProfileSections() async {
    profileReads++;
    return {'profileVersion': 13};
  }

  @override
  Future<List<Map<String, dynamic>>> getPlanHistory() =>
      historyResult?.future ?? Future.value(const []);

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

class _DelayedPlanApi extends ApiClient {
  final current = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> getCurrentPlan() => current.future;
}

Future<void> _pump(
  WidgetTester tester,
  _FakePlanApi api, {
  bool autoPreview = false,
  VoidCallback? onConfirmed,
  double width = 800,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
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

  test('重算预览保留令牌、计划基线和档案版本', () {
    final data = PlanData.fromJson({
      'state': 'PREVIEW',
      'planId': 'plan-1',
      'previewId': 'preview-1',
      'baseVersion': 3,
      'previewVersion': 4,
      'profileVersion': 12,
      'plan': _plan(status: 'PREVIEW'),
    });

    expect(data.previewId, 'preview-1');
    expect(data.baseVersion, 3);
    expect(data.previewVersion, 4);
    expect(data.profileVersion, 12);
  });

  test('会话清空后旧账户的在途计划响应不会回填', () async {
    final api = _DelayedPlanApi();
    final controller = PlanController(api);
    final loading = controller.load();

    controller.reset();
    api.current.complete(_plan());
    await loading;

    expect(controller.state.data, isNull);
    expect(controller.state.loading, isTrue);
  });

  test('确认旧预览冲突后刷新档案和当前计划', () async {
    final api = _FakePlanApi(_plan(needsRecalculation: true));
    final controller = PlanController(api);
    await controller.load();
    await controller.prepareRecalculation();
    api.confirmConflict = true;

    final ok = await controller.confirmRecalculation();

    expect(ok, isFalse);
    expect(api.confirmedExpectedVersion, 1);
    expect(api.confirmedPreviewId, 'preview-1');
    expect(api.profileReads, 1);
    expect(api.currentReads, 2);
    expect(controller.state.recalculationPreview, isFalse);
    expect(controller.state.data!.kind, PlanKind.paused);
    expect(controller.state.error, '健康档案已更新，请重新生成计划预览');
  });

  test('重算失败切换到风险或未开放专用状态且不泄露旧目标', () async {
    for (final entry in {
      'PLAN_RISK_BLOCKED': PlanKind.risk,
      'PLAN_GOAL_UNSUPPORTED': PlanKind.unsupported,
    }.entries) {
      final api = _FakePlanApi(
        _plan(needsRecalculation: true),
        recalculationErrorCode: entry.key,
      );
      final controller = PlanController(api);
      await controller.load();

      final ok = await controller.prepareRecalculation();

      expect(ok, isFalse);
      expect(controller.state.data!.kind, entry.value);
      expect(controller.state.data!.raw, isEmpty);
      expect(controller.state.data!.targetKcal, 0);
      expect(controller.state.error, isNull);
    }
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

  testWidgets('公式版本使用中文名称而不是内部规则码', (tester) async {
    await _pump(tester, _FakePlanApi(_plan()));

    await _tapVisible(tester, '为什么这样安排');

    expect(find.text('减脂公式 V1'), findsOneWidget);
    expect(find.text('FAT_LOSS_V1'), findsNothing);
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

  testWidgets('切换账户后不展示上一账户延迟返回的计划历史', (tester) async {
    final api = _FakePlanApi(_plan());
    final history = Completer<List<Map<String, dynamic>>>();
    api.historyResult = history;

    Future<void> pumpRevision(int revision) async {
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
                sessionRevision: revision,
                onProtectedAction: (_) {},
                onConfirmed: () {},
                onEditProfile: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpRevision(1);
    await _tapVisible(tester, '查看历史版本');
    await pumpRevision(2);
    history.complete([
      {'version': 1, 'createdAt': '2026-09-01T08:00:00Z'},
    ]);
    await tester.pumpAndSettle();

    expect(find.text('历史版本'), findsNothing);
  });

  testWidgets('重新计算先预览变化，取消保留旧计划，确认后才生效', (tester) async {
    final api = _FakePlanApi(
      _plan(needsRecalculation: true),
      preview: {
        ..._plan(status: 'PREVIEW'),
        'targetKcal': 1600,
      },
    );
    await _pump(tester, api);
    await _tapVisible(tester, '重新计算');
    expect(api.previewed, 1);
    expect(api.recalculated, 0);
    expect(find.text('新计划预览'), findsOneWidget);
    expect(find.textContaining('1700 → 1600'), findsOneWidget);
    await _tapVisible(tester, '暂不采用');
    expect(find.text('需要重新计算'), findsOneWidget);
    expect(find.text('1700'), findsOneWidget);
    expect(api.recalculated, 0);

    await _tapVisible(tester, '重新计算');
    await _tapVisible(tester, '确认使用新计划');
    expect(api.recalculated, 1);
  });

  testWidgets('首次预览显示暂不采用且 Android 返回会重新加载当前计划', (tester) async {
    final api = _FakePlanApi({
      'status': 'EMPTY',
    }, preview: _plan(status: 'PREVIEW'));
    await _pump(tester, api, autoPreview: true);
    expect(find.text('暂不采用'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('计划预览'), findsNothing);
    expect(find.text('还没有减脂计划'), findsOneWidget);
    expect(api.currentReads, 2);
  });

  testWidgets('重算预览时 Android 返回等同取消', (tester) async {
    final api = _FakePlanApi(
      _plan(needsRecalculation: true),
      preview: {
        ..._plan(status: 'PREVIEW'),
        'targetKcal': 1600,
      },
    );
    await _pump(tester, api);
    await _tapVisible(tester, '重新计算');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('新计划预览'), findsNothing);
    expect(find.text('需要重新计算'), findsOneWidget);
    expect(find.text('1700'), findsOneWidget);
    expect(api.recalculated, 0);
  });

  testWidgets('320 和 360 宽度配合 2.0 字体时摘要与目标不溢出', (tester) async {
    for (final width in [320.0, 360.0]) {
      await _pump(tester, _FakePlanApi(_plan()), width: width, textScale: 2);
      expect(find.text('每日目标热量'), findsOneWidget);
      expect(find.text('运动'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '宽度 $width');
    }
  });

  testWidgets('历史版本弹层可滚动并显示本地中文日期和 6px 顶部圆角', (tester) async {
    final api = _FakePlanApi(_plan());
    api.historyResult = Completer<List<Map<String, dynamic>>>()
      ..complete(
        List.generate(
          20,
          (index) => {'version': index + 1, 'createdAt': '2026-09-01T08:05:00'},
        ),
      );
    await _pump(tester, api, width: 320, textScale: 2);

    await _tapVisible(tester, '查看历史版本');

    expect(find.text('2026年9月1日 08:05'), findsWidgets);
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    final shape = sheet.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius.resolve(TextDirection.ltr).topLeft.x, 6);
    await tester.scrollUntilVisible(
      find.text('版本 20'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('版本 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新并重新生成预览不会复用旧调整', (tester) async {
    final api = _FakePlanApi({'status': 'EMPTY'});
    await _pump(tester, api);
    await _tapVisible(tester, '生成减脂计划');
    await _tapVisible(tester, '调整目标');
    await tester.tap(find.text('保存调整'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('刷新计划'));
    await tester.tap(find.byTooltip('刷新计划'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, '生成减脂计划');
    await _tapVisible(tester, '确认采用计划');

    expect(api.confirmed, 1);
    expect(api.confirmedAdjustments, isNull);
  });

  testWidgets('确认、暂停和恢复调用计划接口', (tester) async {
    final previewApi = _FakePlanApi(_plan(status: 'PREVIEW'));
    var enteredToday = false;
    await _pump(tester, previewApi, onConfirmed: () => enteredToday = true);
    await _tapVisible(tester, '确认采用计划');
    expect(previewApi.confirmed, 1);
    expect(enteredToday, isTrue);

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
