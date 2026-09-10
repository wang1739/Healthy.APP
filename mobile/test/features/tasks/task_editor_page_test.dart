import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/tasks/application/task_controller.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/tasks/presentation/task_editor_page.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiClient {
  Map<String, dynamic>? saved;
  String? updatedTemplate;
  @override
  Future<TaskDay> getTaskDay(DateTime date) async => TaskDay.fromJson({
    'date': formatLocalDate(date),
    'timeline': const [],
    'allDay': const [],
  });
  @override
  Future<TaskWeek> getTaskWeek(DateTime date) async => TaskWeek.fromJson({
    'startDate': formatLocalDate(date),
    'endDate': formatLocalDate(date),
  });
  @override
  Future<TaskMutationResult> createTask(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    saved = data;
    return TaskMutationResult.fromJson({
      'instance': {
        'id': 'i1',
        ...data,
        'status': 'PENDING',
        'currentLocalDate': '2026-09-10',
      },
    });
  }

  @override
  Future<TaskMutationResult> updateTaskTemplate(
    String id,
    Map<String, dynamic> data,
  ) async {
    updatedTemplate = id;
    saved = data;
    return TaskMutationResult.fromJson({
      'instance': {
        'id': 'i1',
        'templateId': id,
        ...data,
        'status': 'PENDING',
        'currentLocalDate': '2026-09-10',
      },
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Api api, {
  TaskInstance? initialTask,
}) async {
  SharedPreferences.setMockInitialValues({});
  final controller = TaskController(
    api,
    accountKey: 'a',
    now: () => DateTime(2026, 9, 10, 9),
    initialDate: DateTime(2026, 9, 10),
  );
  await controller.load(DateTime(2026, 9, 10));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: TaskEditorPage(
        controller: controller,
        accountKey: 'a',
        selectedDate: DateTime(2026, 9, 10),
        scheduler: TaskNotificationScheduler(
          requestPermission: () async => true,
        ),
        initialTask: initialTask,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('标题校验、原生选择、重复和提醒字段完整', (tester) async {
    final api = _Api();
    await _pump(tester, api);
    expect(find.text('任务名称'), findsOneWidget);
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('普通'), findsOneWidget);
    expect(find.text('全天任务'), findsOneWidget);
    expect(find.text('不重复'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('提醒'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('不提醒'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-editor-save')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('task-title')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('请输入任务名称'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('task-title')), '学习 Flutter');
    await tester.tap(find.byKey(const Key('task-editor-save')));
    await tester.pumpAndSettle();
    expect(api.saved?['title'], '学习 Flutter');
    expect(api.saved, isNot(contains('userId')));
  });

  testWidgets('输入框与主要控件使用 6px 圆角', (tester) async {
    await _pump(tester, _Api());
    final field = tester.widget<TextField>(find.byKey(const Key('task-title')));
    final border = field.decoration!.border! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('编辑重复任务明确选择仅今天或之后安排', (tester) async {
    final api = _Api();
    final task = TaskInstance.fromJson({
      'id': 'i1',
      'templateId': 't1',
      'templateVersion': 2,
      'title': '每日复盘',
      'source': 'USER',
      'category': 'WORK',
      'priority': 'NORMAL',
      'status': 'PENDING',
      'currentLocalDate': '2026-09-10',
      'recurrenceType': 'DAILY',
    });
    await _pump(tester, api, initialTask: task);
    await tester.tap(find.byKey(const Key('task-editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('仅修改今天'), findsOneWidget);
    expect(find.text('之后都按此安排'), findsOneWidget);
    await tester.tap(find.text('之后都按此安排'));
    await tester.pumpAndSettle();
    expect(api.updatedTemplate, 't1');
  });
}
