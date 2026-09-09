import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/activity/presentation/activity_page.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class _ActivityApi extends ApiClient {
  @override
  Future<ActivityDay> getActivityDay(DateTime date) async =>
      ActivityDay.fromJson({
        'date': formatLocalDate(date),
        'status': 'READY',
        'recordCount': 1,
        'totalDurationMinutes': 30,
        'totalKcal': 180,
        'weightKg': 60,
        'records': [
          {
            'id': 'r1',
            'activityTypeId': 'running',
            'activityName': '跑步',
            'intensity': 'MEDIUM',
            'durationMinutes': 30,
            'occurredAt': '${formatLocalDate(date)}T08:00:00+08:00',
            'estimatedKcal': 180,
            'finalKcal': 200,
            'calorieSource': 'USER_OVERRIDE',
          },
        ],
      });

  @override
  Future<ActivityWeek> getActivityWeek(DateTime date) async =>
      ActivityWeek.fromJson({
        'weekStart': '2026-09-07',
        'weekEnd': '2026-09-13',
        'exerciseDays': 2,
        'durationMinutes': 75,
        'totalKcal': 420,
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
}

Future<void> _pump(
  WidgetTester tester,
  UserAccess access, {
  ValueChanged<String>? protected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: ActivityPage(
          api: _ActivityApi(),
          access: access,
          sessionKey: 'u1',
          onProtectedAction: protected ?? (_) {},
          initialDate: DateTime(2026, 9, 9),
          now: () => DateTime(2026, 9, 9, 10),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('展示当天汇总、本周状态和记录，并支持日期导航', (tester) async {
    await _pump(tester, UserAccess.profileComplete);

    expect(find.text('运动管理'), findsOneWidget);
    expect(find.text('1 次'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
    expect(find.text('180 kcal'), findsOneWidget);
    expect(find.text('生成计划后可查看目标进度'), findsOneWidget);
    expect(find.textContaining('已手动修改'), findsOneWidget);

    await tester.tap(find.byTooltip('前一天'));
    await tester.pumpAndSettle();
    expect(find.text('返回今天'), findsOneWidget);
    await tester.tap(find.text('返回今天'));
    await tester.pumpAndSettle();
    expect(find.text('9月9日'), findsOneWidget);
  });

  testWidgets('游客和未建档用户进入权限闭环', (tester) async {
    String? action;
    await _pump(tester, UserAccess.guest, protected: (value) => action = value);
    expect(find.text('登录后记录运动'), findsOneWidget);
    await tester.tap(find.text('登录并继续'));
    expect(action, '记录运动');

    await _pump(
      tester,
      UserAccess.profileIncomplete,
      protected: (value) => action = value,
    );
    expect(find.text('完善健康档案后记录运动'), findsOneWidget);
    await tester.tap(find.text('去完善健康档案'));
    expect(action, '记录运动');
  });

  testWidgets('删除使用中文确认框', (tester) async {
    await _pump(tester, UserAccess.profileComplete);
    await tester.tap(find.byTooltip('删除跑步'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条运动记录？'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}
