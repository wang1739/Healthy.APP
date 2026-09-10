import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/tasks/application/task_controller.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/tasks/presentation/task_editor_page.dart';
import 'package:healthy/features/tasks/presentation/task_settings_sheet.dart';
import 'package:healthy/features/tasks/presentation/task_week_overview_sheet.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({
    required this.api,
    required this.access,
    required this.accountKey,
    required this.onProtectedAction,
    required this.onHealthTaskRequested,
    this.initialDate,
    this.initialInstanceId,
    this.now,
    this.notificationScheduler,
    this.onChanged,
    this.openEditorOnStart = false,
    super.key,
  });
  final ApiClient api;
  final UserAccess access;
  final String accountKey;
  final ValueChanged<String> onProtectedAction;
  final ValueChanged<String> onHealthTaskRequested;
  final DateTime? initialDate;
  final String? initialInstanceId;
  final DateTime Function()? now;
  final TaskNotificationScheduler? notificationScheduler;
  final VoidCallback? onChanged;
  final bool openEditorOnStart;
  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage>
    with WidgetsBindingObserver {
  late DateTime _date;
  late TaskProviderKey _key;
  TaskNotificationScheduler get _scheduler =>
      widget.notificationScheduler ?? TaskNotificationScheduler.instance;
  DateTime get _today {
    final value = widget.now?.call() ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final date = widget.initialDate ?? _today;
    _date = DateTime(date.year, date.month, date.day);
    _key = TaskProviderKey(
      widget.api,
      widget.accountKey,
      _date,
      now: widget.now?.call(),
    );
    if (widget.access != UserAccess.guest) {
      _load();
      Future.microtask(() => _scheduler.sync(widget.accountKey));
      if (widget.openEditorOnStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openEditor(ref.read(taskControllerProvider(_key)));
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        widget.access == UserAccess.guest) {
      return;
    }
    final today = _today;
    if (formatLocalDate(today) != formatLocalDate(_date)) {
      setState(() => _date = today);
    }
    _load(force: true);
    unawaited(_scheduler.sync(widget.accountKey));
  }

  void _load({bool force = false}) {
    Future.microtask(
      () => ref.read(taskControllerProvider(_key)).load(_date, force: force),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access == UserAccess.guest) return _guest();
    final controller = ref.watch(taskControllerProvider(_key));
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日任务'),
        actions: [
          IconButton(
            tooltip: '最近 7 天',
            onPressed: () => _showWeek(state.week),
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: '任务勿扰设置',
            onPressed: _showSettings,
            icon: const Icon(Icons.notifications_paused_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: state.day == null && state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.day == null
            ? _error(state.error ?? '任务加载失败', controller)
            : RefreshIndicator(
                onRefresh: controller.refresh,
                child: _content(controller),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: '新增任务',
        onPressed: () => _openEditor(controller),
        icon: const Icon(Icons.add),
        label: const Text('新增任务'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _guest() => Scaffold(
    appBar: AppBar(title: const Text('每日任务')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '示例：安排今天的工作与生活',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Card(
            child: ListTile(
              leading: Icon(Icons.radio_button_unchecked),
              title: Text('上午 10:00 团队会议'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_box_outlined),
              title: Text('今日待办：整理房间'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => widget.onProtectedAction('创建任务'),
            child: const Text('登录并创建任务'),
          ),
        ],
      ),
    ),
  );

  Widget _error(String message, TaskController controller) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: controller.refresh,
            child: const Text('重新加载'),
          ),
        ],
      ),
    ),
  );

  Widget _content(TaskController controller) {
    final state = controller.state;
    final day = state.day!;
    final filter = state.filter;
    bool visible(TaskInstance task) =>
        filter == null || task.category == filter;
    final timeline = day.timeline.where(visible).toList();
    final allDay = day.allDay.where(visible).toList();
    final completed = day.completed.where(visible).toList();
    final skipped = day.skipped.where(visible).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (state.stale) _notice('数据可能不是最新'),
        if (state.actionError != null)
          _notice(state.actionError!, action: controller.retryAction),
        if (widget.initialInstanceId != null &&
            day.byId(widget.initialInstanceId!) == null)
          _notice('该任务已不存在，已返回对应日期'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '前一天',
              onPressed: () => _move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${_date.month}月${_date.day}日',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            IconButton(
              tooltip: '后一天',
              onPressed: () => _move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Center(
          child: TextButton(onPressed: _goToday, child: const Text('返回今天')),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day.summary.completedCount} / ${day.summary.totalCount} 已完成',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: day.summary.totalCount == 0
                      ? 0
                      : day.summary.completedCount / day.summary.totalCount,
                ),
                const SizedBox(height: 8),
                Text(
                  day.summary.overdueCount > 0
                      ? '${day.summary.overdueCount} 项已逾期'
                      : '当前没有逾期任务',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _filterChip(controller, null, '全部'),
            for (final category in TaskCategory.values)
              _filterChip(controller, category, category.label),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => widget.onHealthTaskRequested('健康任务'),
          icon: const Icon(Icons.favorite_outline),
          label: Text(
            widget.access == UserAccess.profileIncomplete
                ? '完善档案后添加健康任务'
                : '管理健康计划任务',
          ),
        ),
        _section('时间线', timeline, controller),
        _section('今日待办', allDay, controller),
        ExpansionTile(
          initiallyExpanded: false,
          title: Text('已完成 ${completed.length}'),
          children: completed
              .map((task) => _taskRow(task, controller))
              .toList(),
        ),
        ExpansionTile(
          initiallyExpanded: false,
          title: Text('已跳过 ${skipped.length}'),
          children: skipped.map((task) => _taskRow(task, controller)).toList(),
        ),
      ],
    );
  }

  Widget _filterChip(
    TaskController controller,
    TaskCategory? value,
    String label,
  ) => FilterChip(
    label: Text(label),
    selected: controller.state.filter == value,
    onSelected: (_) => controller.filter(value),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
  );

  Widget _section(
    String title,
    List<TaskInstance> tasks,
    TaskController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (tasks.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('暂无任务'),
        ),
      for (final task in tasks) _taskRow(task, controller),
    ],
  );

  Widget _taskRow(TaskInstance task, TaskController controller) => Semantics(
    label: '${task.title}，${task.category.label}，${task.priority.label}',
    child: Card(
      key: task.id == widget.initialInstanceId
          ? const Key('highlighted-task')
          : null,
      child: ListTile(
        leading: IconButton(
          key: Key('task-toggle-${task.id}'),
          tooltip: task.completed || task.skipped ? '撤销状态' : '完成任务',
          onPressed: controller.state.busyIds.contains(task.id)
              ? null
              : () => _toggle(task, controller),
          icon: Icon(
            task.completed
                ? Icons.check_circle
                : task.skipped
                ? Icons.remove_circle_outline
                : Icons.radio_button_unchecked,
          ),
        ),
        title: Text(task.title),
        subtitle: Text(
          [
            if (task.currentDueAt != null)
              '${task.currentDueAt!.toLocal().hour.toString().padLeft(2, '0')}:${task.currentDueAt!.toLocal().minute.toString().padLeft(2, '0')}',
            task.category.label,
            task.priority.label,
            task.source.label,
            if (task.overdue) '已逾期',
            if (task.completionSource == TaskCompletionSource.autoHealthData)
              task.completionReason ?? '已由健康记录自动完成',
          ].join(' · '),
        ),
        trailing: IconButton(
          key: Key('task-menu-${task.id}'),
          tooltip: '更多操作',
          onPressed: () => _showActions(task, controller),
          icon: const Icon(Icons.more_horiz),
        ),
      ),
    ),
  );

  Future<void> _toggle(TaskInstance task, TaskController controller) async {
    if (task.completed || task.skipped) {
      await controller.reopen(task.id);
    } else {
      await controller.complete(task.id);
    }
    await _afterChange();
  }

  Future<void> _showActions(
    TaskInstance task,
    TaskController controller,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('跳过'),
              onTap: () => Navigator.pop(context, 'skip'),
            ),
            ListTile(
              title: const Text('稍后 30 分钟'),
              onTap: () => Navigator.pop(context, 'later'),
            ),
            ListTile(
              title: const Text('明天'),
              onTap: () => Navigator.pop(context, 'tomorrow'),
            ),
            ListTile(
              title: const Text('自选时间'),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
            ListTile(
              title: const Text('编辑'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'skip':
        await controller.skip(task.id);
      case 'later':
        await controller.postpone(task.id, {'type': 'LATER'});
      case 'tomorrow':
        await controller.postpone(task.id, {'type': 'TOMORROW'});
      case 'custom':
        await _customPostpone(task, controller);
      case 'edit':
        await _openEditor(controller, task);
        return;
      case 'delete':
        await _delete(task, controller);
        return;
      case null:
        return;
    }
    await _afterChange();
  }

  Future<void> _customPostpone(
    TaskInstance task,
    TaskController controller,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 3650)),
      helpText: '选择延期日期',
      cancelText: '取消',
      confirmText: '下一步',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        task.currentDueAt?.toLocal() ?? DateTime.now(),
      ),
      helpText: '选择延期时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (time == null) return;
    await controller.postpone(task.id, {
      'type': 'CUSTOM',
      'localDate': formatLocalDate(date),
      'localTime':
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    });
  }

  Future<void> _delete(TaskInstance task, TaskController controller) async {
    final scope = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('删除后无法在当前列表恢复，请选择范围。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'instance'),
            child: const Text('仅删除今天'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'template'),
            child: const Text('删除今天及以后'),
          ),
        ],
      ),
    );
    if (scope == 'instance') {
      await controller.deleteInstance(task.id);
    } else if (scope == 'template') {
      if (task.templateId == null) {
        await controller.deleteInstance(task.id);
      } else {
        await controller.deleteTemplate(task.templateId!, _date);
      }
    }
    if (scope != null) await _afterChange();
  }

  Future<void> _openEditor(
    TaskController controller, [
    TaskInstance? task,
  ]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorPage(
          controller: controller,
          accountKey: widget.accountKey,
          selectedDate: _date,
          scheduler: _scheduler,
          initialTask: task,
        ),
      ),
    );
    if (changed == true) await _afterChange();
  }

  Future<void> _afterChange() async {
    widget.onChanged?.call();
    await _scheduler.sync(widget.accountKey);
  }

  void _move(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    ref.read(taskControllerProvider(_key)).load(_date);
  }

  void _goToday() {
    setState(() => _date = _today);
    ref.read(taskControllerProvider(_key)).load(_date);
  }

  void _showWeek(TaskWeek? week) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
    ),
    builder: (_) => TaskWeekOverviewSheet(week: week),
  );

  void _showSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
    ),
    builder: (_) => TaskSettingsSheet(
      api: widget.api,
      accountKey: widget.accountKey,
      scheduler: _scheduler,
    ),
  );

  Widget _notice(String text, {Future<void> Function()? action}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Expanded(child: Text(text)),
        if (action != null)
          TextButton(onPressed: action, child: const Text('重试')),
      ],
    ),
  );
}
