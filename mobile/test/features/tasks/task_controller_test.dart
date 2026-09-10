import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/tasks/application/task_controller.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

TaskDay _day(String date, {String status = 'PENDING', String id = 'i1'}) =>
    TaskDay.fromJson({
      'date': date,
      'status': 'READY',
      'summary': {
        'totalCount': 1,
        'completedCount': status == 'COMPLETED' ? 1 : 0,
        'pendingCount': status == 'PENDING' ? 1 : 0,
      },
      'timeline': [
        {
          'id': id,
          'title': '测试任务',
          'source': 'USER',
          'category': 'WORK',
          'priority': 'NORMAL',
          'status': status,
          'currentLocalDate': date,
          'currentDueAt': '${date}T02:00:00Z',
        },
      ],
    });

TaskWeek _week(String date) =>
    TaskWeek.fromJson({'startDate': date, 'endDate': date, 'expectedCount': 1});

class _Api extends ApiClient {
  bool failLoad = false;
  bool failWrite = false;
  int creates = 0;
  int completes = 0;
  final keys = <String>[];
  final loads = <String, Completer<TaskDay>>{};

  @override
  Future<TaskDay> getTaskDay(DateTime date) {
    final key = formatLocalDate(date);
    if (failLoad) throw DioException(requestOptions: RequestOptions());
    return loads[key]?.future ?? Future.value(_day(key));
  }

  @override
  Future<TaskWeek> getTaskWeek(DateTime date) async =>
      _week(formatLocalDate(date));

  TaskMutationResult result(String status) => TaskMutationResult.fromJson({
    'instance': {
      ..._day('2026-09-10', status: status).timeline.single.toJson(),
      'status': status,
    },
    'day': _day('2026-09-10', status: status).toJson(),
  });

  @override
  Future<TaskMutationResult> createTask(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) async {
    creates++;
    keys.add(idempotencyKey);
    if (failWrite) throw DioException(requestOptions: RequestOptions());
    return result('PENDING');
  }

  @override
  Future<TaskMutationResult> completeTask(
    String id, {
    required String idempotencyKey,
  }) async {
    completes++;
    keys.add(idempotencyKey);
    if (failWrite) throw DioException(requestOptions: RequestOptions());
    return result('COMPLETED');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('最近成功缓存按账号和本地日期隔离，失败时保留并标记陈旧', () async {
    final api = _Api();
    final first = TaskController(
      api,
      accountKey: 'a',
      now: () => DateTime(2026, 9, 10),
    );
    await first.load(DateTime(2026, 9, 10));
    await Future<void>.delayed(Duration.zero);

    api.failLoad = true;
    final sameAccount = TaskController(
      api,
      accountKey: 'a',
      now: () => DateTime(2026, 9, 10),
    );
    await sameAccount.load(DateTime(2026, 9, 10));
    expect(sameAccount.state.day?.timeline.single.title, '测试任务');
    expect(sameAccount.state.stale, isTrue);
    expect(sameAccount.state.error, '数据可能不是最新');

    final otherAccount = TaskController(
      api,
      accountKey: 'b',
      now: () => DateTime(2026, 9, 10),
    );
    await otherAccount.load(DateTime(2026, 9, 10));
    expect(otherAccount.state.day, isNull);
  });

  test('日期切换与页面销毁会丢弃迟到响应', () async {
    final api = _Api();
    api.loads['2026-09-10'] = Completer<TaskDay>();
    api.loads['2026-09-11'] = Completer<TaskDay>();
    final controller = TaskController(api, accountKey: 'a', now: DateTime.now);
    final first = controller.load(DateTime(2026, 9, 10));
    final second = controller.load(DateTime(2026, 9, 11));
    api.loads['2026-09-11']!.complete(_day('2026-09-11', id: 'new'));
    await second;
    api.loads['2026-09-10']!.complete(_day('2026-09-10', id: 'old'));
    await first;
    expect(controller.state.day?.timeline.single.id, 'new');
    controller.dispose();
  });

  test('创建失败保留草稿且重试复用幂等键，成功后清除', () async {
    final api = _Api()..failWrite = true;
    final controller = TaskController(
      api,
      accountKey: 'a',
      now: () => DateTime(2026, 9, 10),
    );
    await controller.load(DateTime(2026, 9, 10));
    final draft = {'title': '测试任务', 'category': 'WORK'};
    await controller.save(draft);
    expect(controller.state.draft, draft);
    api.failWrite = false;
    await controller.retrySave();
    expect(api.keys.toSet(), hasLength(1));
    expect(controller.state.draft, isNull);
  });

  test('完成乐观更新失败精确回滚，重试复用键且防重复点击', () async {
    final api = _Api()..failWrite = true;
    final controller = TaskController(
      api,
      accountKey: 'a',
      now: () => DateTime(2026, 9, 10),
    );
    await controller.load(DateTime(2026, 9, 10));
    final action = controller.complete('i1');
    expect(controller.state.day?.byId('i1')?.completed, isTrue);
    await controller.complete('i1');
    expect(api.completes, 1);
    await action;
    expect(controller.state.day?.byId('i1')?.pending, isTrue);
    expect(controller.state.actionError, isNotNull);

    api.failWrite = false;
    await controller.retryAction();
    expect(api.keys.toSet(), hasLength(1));
    expect(controller.state.day?.byId('i1')?.completed, isTrue);
  });

  test('分类筛选只改变当前展示，不污染缓存键', () async {
    final controller = TaskController(
      _Api(),
      accountKey: 'a',
      now: () => DateTime(2026, 9, 10),
    );
    await controller.load(DateTime(2026, 9, 10));
    controller.filter(TaskCategory.work);
    expect(controller.visibleTasks, hasLength(1));
    controller.filter(TaskCategory.health);
    expect(controller.visibleTasks, isEmpty);
  });
}
