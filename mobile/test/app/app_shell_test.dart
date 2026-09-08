import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/app_shell.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/api/backend_status.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/today/domain/today_data.dart';
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
}

void main() {
  late SessionController session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    session = SessionController(ApiClient());
    await session.skipLogin();
  });

  testWidgets('shows five destinations and switches pages', (tester) async {
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

    for (final label in ['今日', '饮食', '计划', '报告', '我的']) {
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

  testWidgets('今日核心目标进入计划页且待接入操作显示中文说明', (tester) async {
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
    await tester.pump();
    expect(find.text('该记录功能将在后续阶段接入'), findsOneWidget);
  });
}
