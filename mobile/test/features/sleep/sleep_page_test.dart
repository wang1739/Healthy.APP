import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:healthy/features/sleep/presentation/sleep_page.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiClient {
  @override
  Future<SleepDay> getSleepDay(DateTime date) async => SleepDay.fromJson({
    'date': formatLocalDate(date),
    'nightDurationMinutes': 450,
    'napDurationMinutes': 30,
    'targetMinutes': 480,
    'planStatus': 'ACTIVE',
    'records': [
      {
        'id': 's1',
        'recordType': 'NIGHT',
        'startedAt': '2026-09-08T15:30:00Z',
        'endedAt': '2026-09-08T23:00:00Z',
        'wakeLocalDate': '2026-09-09',
        'durationMinutes': 450,
        'qualityScore': 4,
      },
    ],
  });
  @override
  Future<SleepWeek> getSleepWeek(DateTime date) async => SleepWeek.fromJson({
    'startDate': '2026-09-03',
    'endDate': '2026-09-09',
    'averageNightDurationMinutes': 430,
    'targetAchievedDays': 2,
    'averageQuality': 3.8,
    'napTotalMinutes': 60,
    'hasEnoughTrendData': false,
    'targetMinutes': 480,
    'planStatus': 'ACTIVE',
    'dailyPoints': [
      {'date': '2026-09-09', 'nightDurationMinutes': 450},
    ],
  });
}

Future<void> _pump(
  WidgetTester tester,
  UserAccess access, {
  ValueChanged<String>? protected,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1000));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: SleepPage(
          api: _Api(),
          access: access,
          sessionKey: 'u1',
          onProtectedAction: protected ?? (_) {},
          initialDate: DateTime(2026, 9, 9),
          now: () => DateTime(2026, 9, 9, 10),
          reminderScheduler: SleepReminderScheduler(
            cancel: (_) async {},
            schedule: (_, _, _) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('展示昨晚、七天摘要、简单时长条和记录列表', (tester) async {
    await _pump(tester, UserAccess.profileComplete);
    expect(find.text('睡眠管理'), findsOneWidget);
    expect(find.text('7 小时 30 分钟'), findsWidgets);
    expect(find.text('距目标还差 30 分钟'), findsOneWidget);
    expect(find.text('记录不足，继续记录后可查看趋势'), findsOneWidget);
    expect(find.text('夜间睡眠'), findsOneWidget);
    final delete = find.byTooltip('删除夜间睡眠');
    await tester.scrollUntilVisible(
      delete,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('删除这条睡眠记录？'), findsOneWidget);
  });

  testWidgets('游客和未建档用户进入权限闭环', (tester) async {
    String? action;
    await _pump(tester, UserAccess.guest, protected: (value) => action = value);
    await tester.tap(find.text('登录并继续'));
    expect(action, '记录睡眠');
    await _pump(
      tester,
      UserAccess.profileIncomplete,
      protected: (value) => action = value,
    );
    await tester.tap(find.text('去完善健康档案'));
    expect(action, '记录睡眠');
  });

  testWidgets('睡前提醒使用中文并保留一组时间星期设置', (tester) async {
    await _pump(tester, UserAccess.profileComplete);
    await tester.tap(find.byTooltip('睡前提醒'));
    await tester.pumpAndSettle();
    expect(find.text('开启睡前提醒'), findsOneWidget);
    expect(find.text('提醒时间'), findsOneWidget);
    expect(find.text('重复星期'), findsOneWidget);
    expect(find.text('保存提醒设置'), findsOneWidget);
  });
}
