import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/tasks/presentation/task_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiClient {
  Map<String, dynamic>? saved;
  @override
  Future<TaskSettings> getTaskSettings() async => const TaskSettings();
  @override
  Future<TaskSettings> updateTaskSettings(Map<String, dynamic> data) async {
    saved = data;
    return TaskSettings.fromJson({...data, 'version': 1});
  }
}

void main() {
  testWidgets('勿扰默认开启且显示跨午夜默认时段', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TaskSettingsSheet(
            api: api,
            accountKey: 'a',
            scheduler: TaskNotificationScheduler(
              loadNotifications: () async => [],
              loadSettings: () async => const TaskSettings(),
              cancel: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('任务勿扰设置'), findsOneWidget);
    expect(find.text('22:30'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('权限拒绝显示系统设置入口且不影响勿扰保存', (tester) async {
    SharedPreferences.setMockInitialValues({'task_permission_denied_a': true});
    var opened = false;
    final api = _Api();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TaskSettingsSheet(
            api: api,
            accountKey: 'a',
            scheduler: TaskNotificationScheduler(
              loadNotifications: () async => [],
              loadSettings: () async => const TaskSettings(),
              cancel: (_) async {},
              openSettings: () async => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('通知权限未开启，不影响任务保存和使用。'), findsOneWidget);
    await tester.tap(find.text('前往系统设置'));
    expect(opened, isTrue);
    await tester.tap(find.text('保存勿扰设置'));
    await tester.pumpAndSettle();
    expect(api.saved?['quietStartTime'], '22:30');
  });
}
