import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/plan/application/plan_controller.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:healthy/features/today/presentation/today_page.dart';

Map<String, dynamic> overview({
  String planStatus = 'READY',
  String planState = 'ACTIVE',
  String weightStatus = 'READY',
  String moduleStatus = 'COMING_SOON',
  String action = 'VIEW_PLAN',
  String actionTitle = '查看今日目标',
}) => {
  'date': '2026-09-08',
  'plan': {
    'status': planStatus,
    'state': planState,
    if (planStatus == 'READY' && planState != 'RISK_BLOCKED') ...{
      'currentWeek': 2,
      'targetKcal': 1470,
      'proteinG': 110,
      'carbsG': 155,
      'fatG': 45,
      'waterMl': 1900,
      'exerciseDays': 4,
      'exerciseMinutes': 150,
      'sleepHours': 8,
    },
    if (planStatus == 'ERROR') 'message': '该项数据暂时无法加载',
  },
  'weight': {
    'status': weightStatus,
    if (weightStatus == 'READY') ...{
      'valueKg': 62.5,
      'measuredAt': '2026-09-07T08:30:00Z',
    },
  },
  'nutrition': {'status': moduleStatus},
  'hydration': {'status': moduleStatus},
  'activity': {'status': moduleStatus},
  'sleep': {'status': moduleStatus},
  'tasks': {'status': moduleStatus},
  'nextAction': {'type': action, 'title': actionTitle},
};

class _FakeApi extends ApiClient {
  _FakeApi(this.json) : super(dio: Dio());

  Map<String, dynamic> json;
  int todayCalls = 0;
  bool fail = false;

  @override
  Future<TodayData> getToday(DateTime date) async {
    todayCalls++;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return TodayData.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> previewPlan() async => {
    'status': 'PREVIEW',
    'targetKcal': 1600,
  };
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeApi api,
  UserAccess access, {
  VoidCallback? onOpenPlan,
  ValueChanged<String>? onProtectedAction,
  ProviderContainer? container,
  double width = 800,
  double textScale = 1,
  DateTime Function()? now,
  VoidCallback? onOpenActivity,
  VoidCallback? onRecordActivity,
  VoidCallback? onOpenSleep,
  VoidCallback? onRecordSleep,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  final app = MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 900),
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: Scaffold(
        body: TodayPage(
          api: api,
          access: access,
          onOpenPlan: onOpenPlan ?? () {},
          onProtectedAction: onProtectedAction ?? (_) {},
          now: now,
          onOpenActivity: onOpenActivity,
          onRecordActivity: onRecordActivity,
          onOpenSleep: onOpenSleep,
          onRecordSleep: onRecordSleep,
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('游客不请求私人接口且不显示虚构数值', (tester) async {
    final api = _FakeApi(overview());
    String? requested;
    await _pumpPage(
      tester,
      api,
      UserAccess.guest,
      onProtectedAction: (label) => requested = label,
    );

    expect(api.todayCalls, 0);
    expect(find.text('登录后开启你的今日计划'), findsOneWidget);
    expect(find.text('1470'), findsNothing);
    await tester.tap(find.text('登录并开始'));
    expect(requested, '查看个性化今日目标');
  });

  testWidgets('已登录未建档显示完善档案行动且不请求接口', (tester) async {
    final api = _FakeApi(overview());
    String? requested;
    await _pumpPage(
      tester,
      api,
      UserAccess.profileIncomplete,
      onProtectedAction: (label) => requested = label,
    );

    expect(api.todayCalls, 0);
    expect(find.text('完善健康档案'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '完善健康档案'));
    expect(requested, '完善健康档案');
  });

  testWidgets('已生效计划展示真实目标、最新体重和周数', (tester) async {
    final api = _FakeApi(overview());
    var opened = false;
    await _pumpPage(
      tester,
      api,
      UserAccess.profileComplete,
      onOpenPlan: () => opened = true,
    );

    for (final text in [
      '1470 kcal',
      '110 g',
      '155 g',
      '45 g',
      '1900 ml',
      '4 天 / 150 分钟',
      '8.0 小时',
      '62.5 kg',
      '第 2 周',
    ]) {
      expect(find.textContaining(text), findsWidgets);
    }
    final action = find.text('查看今日目标').last;
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    expect(opened, isTrue);
  });

  testWidgets('无计划和内存预览分别进入生成与继续确认', (tester) async {
    final noPlanApi = _FakeApi(
      overview(
        planStatus: 'EMPTY',
        planState: 'EMPTY',
        action: 'CREATE_PLAN',
        actionTitle: '生成减脂计划',
      ),
    );
    await _pumpPage(tester, noPlanApi, UserAccess.profileComplete);
    expect(find.text('生成计划后，这里会显示你的每日目标'), findsOneWidget);
    expect(find.text('生成减脂计划'), findsWidgets);

    final previewApi = _FakeApi(noPlanApi.json);
    final container = ProviderContainer();
    await container.read(planControllerProvider(previewApi)).generate();
    await _pumpPage(
      tester,
      previewApi,
      UserAccess.profileComplete,
      container: container,
    );
    expect(find.text('继续确认计划'), findsWidgets);
    expect(find.text('1600'), findsNothing);
    container.dispose();
  });

  testWidgets('暂停、风险和待重算状态使用中文说明', (tester) async {
    for (final values in [
      ['PAUSED', '查看暂停的计划'],
      ['RISK_BLOCKED', '查看健康建议'],
      ['NEEDS_RECALCULATION', '计划需要重新计算'],
    ]) {
      await _pumpPage(
        tester,
        _FakeApi(overview(planState: values[0], actionTitle: values[1])),
        UserAccess.profileComplete,
      );
      expect(find.textContaining(values[1]), findsWidgets);
      if (values[0] == 'RISK_BLOCKED') {
        expect(find.text('今日执行'), findsNothing);
        expect(find.textContaining('1470 kcal'), findsNothing);
      }
    }
  });

  testWidgets('模块待接入、空数据和单模块失败均有中文状态', (tester) async {
    await _pumpPage(
      tester,
      _FakeApi(overview(planStatus: 'ERROR', weightStatus: 'EMPTY')),
      UserAccess.profileComplete,
    );
    expect(find.text('记录功能待接入'), findsWidgets);
    expect(find.text('暂无最新体重'), findsOneWidget);
    expect(find.text('该项数据暂时无法加载'), findsWidgets);
  });

  testWidgets('计划失败不覆盖真实饮食，饮食失败不展示计划目标', (tester) async {
    final planFailure = overview(planStatus: 'ERROR');
    planFailure['nutrition'] = {
      'status': 'READY',
      'consumedKcal': 321,
      'proteinG': 20.5,
      'carbsG': 30.2,
      'fatG': 8.1,
    };
    await _pumpPage(tester, _FakeApi(planFailure), UserAccess.profileComplete);
    expect(find.text('321 kcal'), findsOneWidget);
    expect(find.text('数据已更新'), findsNWidgets(2));

    final nutritionFailure = overview();
    nutritionFailure['nutrition'] = {
      'status': 'ERROR',
      'message': '该项数据暂时无法加载',
    };
    await _pumpPage(
      tester,
      _FakeApi(nutritionFailure),
      UserAccess.profileComplete,
    );
    expect(find.text('1470 kcal'), findsOneWidget);
  });

  testWidgets('整体网络失败显示重新加载', (tester) async {
    final api = _FakeApi(overview())..fail = true;
    await _pumpPage(tester, api, UserAccess.profileComplete);
    expect(find.text('网络连接失败，请稍后重试'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });

  testWidgets('账户切换后请求失败也不显示上一账户的缓存', (tester) async {
    final api = _FakeApi(overview());
    final container = ProviderContainer();
    await _pumpPage(
      tester,
      api,
      UserAccess.profileComplete,
      container: container,
    );
    expect(find.text('1470 kcal'), findsWidgets);

    await _pumpPage(tester, api, UserAccess.guest, container: container);
    api.fail = true;
    await _pumpPage(
      tester,
      api,
      UserAccess.profileComplete,
      container: container,
    );

    expect(find.text('1470 kcal'), findsNothing);
    expect(find.text('网络连接失败，请稍后重试'), findsOneWidget);
    container.dispose();
  });

  testWidgets('后台恢复仅在设备本地日期变化后刷新', (tester) async {
    var now = DateTime(2026, 9, 8, 10);
    final api = _FakeApi(overview());
    await _pumpPage(tester, api, UserAccess.profileComplete, now: () => now);
    expect(api.todayCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.todayCalls, 1);

    now = DateTime(2026, 9, 9, 8);
    api.json = {...api.json, 'date': '2026-09-09'};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.todayCalls, 2);
    expect(find.textContaining('9月9日'), findsOneWidget);
  });

  testWidgets('窄屏和大字体仍可访问所有核心区域', (tester) async {
    await _pumpPage(
      tester,
      _FakeApi(overview()),
      UserAccess.profileComplete,
      width: 320,
      textScale: 2,
    );
    expect(find.text('今日概览'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('快捷操作'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('快捷操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('运动摘要和记录运动分别使用两个真实入口', (tester) async {
    final json = overview(moduleStatus: 'READY');
    json['activity'] = {
      'status': 'READY',
      'todayDurationMinutes': 30,
      'todayKcal': 180,
      'todayRecordCount': 1,
      'weekExerciseDays': 2,
      'weekDurationMinutes': 75,
      'targetExerciseDays': 4,
      'targetDurationMinutes': 150,
    };
    var opened = 0;
    var recorded = 0;
    await _pumpPage(
      tester,
      _FakeApi(json),
      UserAccess.profileComplete,
      onOpenActivity: () => opened++,
      onRecordActivity: () => recorded++,
    );

    expect(find.text('30 分钟 · 180 kcal'), findsOneWidget);
    final summaryText = find.text('30 分钟 · 180 kcal');
    await tester.scrollUntilVisible(
      summaryText,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.ancestor(of: summaryText, matching: find.byType(InkWell)),
    );
    expect(opened, 1);
    final action = find.text('记录运动');
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    expect(recorded, 1);
  });

  testWidgets('睡眠摘要和记录睡眠分别使用两个真实入口', (tester) async {
    final json = overview(moduleStatus: 'READY');
    json['sleep'] = {
      'status': 'READY',
      'nightDurationMinutes': 450,
      'targetMinutes': 480,
      'differenceMinutes': -30,
      'qualityScore': 4,
      'qualityLabel': '良好',
      'napDurationMinutes': 30,
      'hasEnoughTrendData': true,
    };
    var opened = 0;
    var recorded = 0;
    await _pumpPage(
      tester,
      _FakeApi(json),
      UserAccess.profileComplete,
      onOpenSleep: () => opened++,
      onRecordSleep: () => recorded++,
    );
    final summary = find.text('7 小时 30 分钟 · 良好');
    expect(summary, findsOneWidget);
    await tester.scrollUntilVisible(
      summary,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.ancestor(of: summary, matching: find.byType(InkWell)),
    );
    expect(opened, 1);
    final action = find.text('记录睡眠');
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    expect(recorded, 1);
  });

  testWidgets('主要弹层使用 6px 圆角', (tester) async {
    await _pumpPage(
      tester,
      _FakeApi(overview(planState: 'RISK_BLOCKED')),
      UserAccess.profileComplete,
    );

    final theme = Theme.of(tester.element(find.byType(TodayPage)));
    final shape = theme.dialogTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(6));
  });
}
