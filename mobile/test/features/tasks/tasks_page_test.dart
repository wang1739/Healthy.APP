import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/tasks/presentation/tasks_page.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiClient {
  int loads = 0;
  int completes = 0;
  @override
  Future<TaskDay> getTaskDay(DateTime date) async {
    loads++;
    final value = formatLocalDate(date);
    return TaskDay.fromJson({
      'date': value,
      'status': 'READY',
      'summary': {
        'totalCount': 4,
        'completedCount': 1,
        'pendingCount': 2,
        'overdueCount': 1,
        'nextTaskId': 'work',
      },
      'timeline': [
        {
          'id': 'work',
          'title': '团队会议',
          'source': 'USER',
          'category': 'WORK',
          'priority': 'IMPORTANT',
          'status': 'PENDING',
          'currentLocalDate': value,
          'currentDueAt': '${value}T02:00:00Z',
          'overdue': true,
        },
      ],
      'allDay': [
        {
          'id': 'life',
          'title': '整理房间',
          'source': 'USER',
          'category': 'LIFE',
          'priority': 'NORMAL',
          'status': 'PENDING',
          'currentLocalDate': value,
          'allDay': true,
        },
      ],
      'completed': [
        {
          'id': 'health',
          'title': '记录早餐',
          'source': 'PLAN',
          'category': 'HEALTH',
          'priority': 'NORMAL',
          'status': 'COMPLETED',
          'completionSource': 'AUTO_HEALTH_DATA',
          'completionReason': '已记录早餐',
          'currentLocalDate': value,
        },
      ],
      'skipped': [
        {
          'id': 'study',
          'title': '背单词',
          'source': 'USER',
          'category': 'STUDY',
          'priority': 'NORMAL',
          'status': 'SKIPPED',
          'currentLocalDate': value,
        },
      ],
    });
  }

  @override
  Future<TaskWeek> getTaskWeek(DateTime date) async => TaskWeek.fromJson({
    'startDate': '2026-09-04',
    'endDate': '2026-09-10',
    'expectedCount': 10,
    'completedCount': 6,
    'skippedCount': 1,
    'postponedCount': 2,
    'overdueCount': 1,
    'completionRate': 0.6,
    'categories': [
      {'category': 'WORK', 'expectedCount': 5, 'completedCount': 4},
    ],
  });

  TaskMutationResult _result(String status) => TaskMutationResult.fromJson({
    'instance': {
      'id': 'work',
      'title': '团队会议',
      'source': 'USER',
      'category': 'WORK',
      'priority': 'IMPORTANT',
      'status': status,
      'currentLocalDate': '2026-09-10',
    },
  });

  @override
  Future<TaskMutationResult> completeTask(
    String id, {
    required String idempotencyKey,
  }) async {
    completes++;
    return _result('COMPLETED');
  }

  @override
  Future<TaskSettings> getTaskSettings() async => const TaskSettings();
}

TaskNotificationScheduler _scheduler(_Api api) => TaskNotificationScheduler(
  api: api,
  loadNotifications: () async => [],
  loadSettings: () async => const TaskSettings(),
  schedule: (_, _, _, _) async {},
  cancel: (_) async {},
  reportEvents: (_) async {},
);

Future<void> _pump(
  WidgetTester tester,
  UserAccess access, {
  _Api? api,
  ValueChanged<String>? protected,
  ValueChanged<String>? health,
}) async {
  await tester.binding.setSurfaceSize(const Size(720, 1000));
  SharedPreferences.setMockInitialValues({});
  final client = api ?? _Api();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: TasksPage(
          api: client,
          access: access,
          accountKey: 'a',
          onProtectedAction: protected ?? (_) {},
          onHealthTaskRequested: health ?? (_) {},
          initialDate: DateTime(2026, 9, 10),
          now: () => DateTime(2026, 9, 10, 9),
          notificationScheduler: _scheduler(client),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('展示日期、完成进度、时间线、今日待办和六类筛选', (tester) async {
    await _pump(tester, UserAccess.profileComplete);
    expect(find.text('每日任务'), findsOneWidget);
    expect(find.text('1 / 4 已完成'), findsOneWidget);
    expect(find.text('时间线'), findsOneWidget);
    expect(find.text('团队会议'), findsOneWidget);
    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('整理房间'), findsOneWidget);
    for (final label in ['全部', '健康', '工作', '生活', '学习', '其他']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('已完成 1'), findsOneWidget);
    expect(find.text('已跳过 1'), findsOneWidget);
  });

  testWidgets('日期导航、返回今天、分类过滤和完成操作可用', (tester) async {
    final api = _Api();
    await _pump(tester, UserAccess.profileComplete, api: api);
    await tester.tap(find.byTooltip('后一天'));
    await tester.pumpAndSettle();
    expect(api.loads, greaterThan(1));
    await tester.tap(find.text('返回今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '健康'));
    await tester.pump();
    expect(find.text('团队会议'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, '全部'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-toggle-work')));
    await tester.pumpAndSettle();
    expect(api.completes, 1);
  });

  testWidgets('任务菜单提供跳过、三种延期、编辑和两种删除范围', (tester) async {
    await _pump(tester, UserAccess.profileComplete);
    await tester.tap(find.byKey(const Key('task-menu-work')));
    await tester.pumpAndSettle();
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('稍后 30 分钟'), findsOneWidget);
    expect(find.text('明天'), findsOneWidget);
    expect(find.text('自选时间'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('仅删除今天'), findsOneWidget);
    expect(find.text('删除今天及以后'), findsOneWidget);
  });

  testWidgets('最近七天只展示真实数量和进度', (tester) async {
    await _pump(tester, UserAccess.profileComplete);
    await tester.tap(find.byTooltip('最近 7 天'));
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天概览'), findsOneWidget);
    expect(find.text('应完成 10'), findsOneWidget);
    expect(find.text('已完成 6'), findsOneWidget);
    expect(find.text('已延期 2'), findsOneWidget);
    expect(find.text('工作 4 / 5'), findsOneWidget);
  });

  testWidgets('游客看示例且操作进入登录，未建档可新增个人任务', (tester) async {
    String? action;
    final guestApi = _Api();
    await _pump(
      tester,
      UserAccess.guest,
      api: guestApi,
      protected: (value) => action = value,
    );
    expect(find.text('示例：安排今天的工作与生活'), findsOneWidget);
    expect(guestApi.loads, 0);
    await tester.tap(find.text('登录并创建任务'));
    expect(action, '创建任务');

    await _pump(tester, UserAccess.profileIncomplete);
    await tester.tap(find.byTooltip('新增任务'));
    await tester.pumpAndSettle();
    expect(find.text('新增任务'), findsWidgets);
  });
}
