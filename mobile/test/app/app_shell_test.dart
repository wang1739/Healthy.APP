import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/app_shell.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/api/backend_status.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TodayApi extends ApiClient {
  @override
  Future<TodayData> getToday(DateTime date) async => TodayData.fromJson({
    'date': formatLocalDate(date),
    'plan': {
      'status': 'READY',
      'state': 'ACTIVE',
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
    'weight': {'status': 'EMPTY'},
    'nutrition': {'status': 'COMING_SOON'},
    'hydration': {'status': 'COMING_SOON'},
    'activity': {'status': 'COMING_SOON'},
    'sleep': {'status': 'COMING_SOON'},
    'tasks': {'status': 'COMING_SOON'},
    'nextAction': {'type': 'VIEW_PLAN', 'title': '查看今日目标'},
  });

  @override
  Future<Map<String, dynamic>> getCurrentPlan() async => {'state': 'EMPTY'};

  @override
  Future<ActivityDay> getActivityDay(DateTime date) async =>
      ActivityDay.fromJson({
        'date': formatLocalDate(date),
        'weightKg': 60,
        'records': const [],
      });

  @override
  Future<ActivityWeek> getActivityWeek(DateTime date) async =>
      ActivityWeek.fromJson({
        'weekStart': formatLocalDate(date),
        'weekEnd': formatLocalDate(date),
        'planStatus': 'NO_PLAN',
      });

  @override
  Future<List<ActivityType>> getActivityTypes({String query = ''}) async => [
    const ActivityType(
      id: 'running',
      name: '跑步',
      category: 'CARDIO',
      scope: ActivityTypeScope.system,
      lowMet: 4,
      mediumMet: 6,
      highMet: 8,
    ),
  ];

  @override
  Future<SleepDay> getSleepDay(DateTime date) async => SleepDay.fromJson({
    'date': formatLocalDate(date),
    'status': 'EMPTY',
    'records': const [],
    'planState': 'NO_PLAN',
  });

  @override
  Future<SleepWeek> getSleepWeek(DateTime date) async => SleepWeek.fromJson({
    'startDate': formatLocalDate(date),
    'endDate': formatLocalDate(date),
    'status': 'EMPTY',
    'days': const [],
    'planState': 'NO_PLAN',
  });
}

void main() {
  late SessionController session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    session = SessionController(ApiClient());
    await session.skipLogin();
  });

  testWidgets('shows six destinations and switches pages', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['今日', '饮食', '计划', '报告', '我的', '饮水']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('今日概览'), findsOneWidget);

    await tester.tap(find.text('饮食'));
    await tester.pumpAndSettle();

    expect(find.text('饮食记录'), findsOneWidget);
  });

  testWidgets('游客使用个性化功能时显示登录引导', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('饮食'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始记录'));
    await tester.pumpAndSettle();

    expect(find.text('登录后开启个性化服务'), findsOneWidget);
    expect(find.text('登录并继续'), findsOneWidget);
    expect(find.text('暂时看看'), findsOneWidget);
  });

  testWidgets('我的页面显示游客状态和登录入口', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('游客模式'), findsOneWidget);
    expect(find.text('登录并开启个性化服务'), findsOneWidget);
  });

  testWidgets('uses the compact six-pixel card radius', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Card).first);
    final shape = Theme.of(context).cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('今日核心目标进入计划页且记录饮食进入饮食页', (tester) async {
    session = SessionController(_TodayApi());
    session.completeProfile();
    session.consumePendingFeature();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('今日核心目标，点击查看计划'));
    await tester.pumpAndSettle();
    expect(find.text('减脂计划'), findsOneWidget);

    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    final action = find.text('记录饮食');
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('饮食记录'), findsOneWidget);
  });

  testWidgets('今日记录运动直接进入运动表单且不增加底部导航', (tester) async {
    session = SessionController(_TodayApi());
    session.completeProfile();
    session.consumePendingFeature();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.text('记录运动');
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('记录运动'), findsWidgets);
    expect(find.byKey(const Key('activity-save')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
      hasLength(6),
    );
  });

  testWidgets('今日记录睡眠直接进入睡眠表单且不增加底部导航', (tester) async {
    session = SessionController(_TodayApi());
    session.completeProfile();
    session.consumePendingFeature();
    final scheduler = SleepReminderScheduler(
      requestPermission: () async => true,
      schedule: (_, _, _) async {},
      cancel: (_) async {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session, sleepReminderScheduler: scheduler),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.text('记录睡眠');
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sleep-save')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
      hasLength(6),
    );
  });

  testWidgets('应用恢复前台时重新安排当前账号睡眠提醒', (tester) async {
    session = SessionController(_TodayApi());
    session.completeProfile();
    session.consumePendingFeature();
    var cancellations = 0;
    final scheduler = SleepReminderScheduler(
      cancel: (_) async => cancellations++,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(session: session, sleepReminderScheduler: scheduler),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(cancellations, 7);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(cancellations, 14);
  });
}
