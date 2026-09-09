import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/activity/application/activity_controller.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/activity/presentation/activity_record_page.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({
    required this.api,
    required this.access,
    required this.sessionKey,
    required this.onProtectedAction,
    this.onChanged,
    this.openRecordOnStart = false,
    this.initialDate,
    this.now,
    super.key,
  });

  final ApiClient api;
  final UserAccess access;
  final String sessionKey;
  final ValueChanged<String> onProtectedAction;
  final VoidCallback? onChanged;
  final bool openRecordOnStart;
  final DateTime? initialDate;
  final DateTime Function()? now;

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  late DateTime _date;
  late ActivityProviderKey _key;
  bool _openedInitialRecord = false;

  DateTime get _today {
    final value = widget.now?.call() ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? _today;
    _date = DateTime(initial.year, initial.month, initial.day);
    _setKey();
    _load();
    if (widget.openRecordOnStart &&
        widget.access == UserAccess.profileComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditor());
    }
  }

  void _setKey() {
    _key = ActivityProviderKey(
      widget.api,
      widget.sessionKey,
      _date,
      now: widget.now?.call(),
    );
  }

  void _load() {
    if (widget.access != UserAccess.profileComplete) return;
    Future.microtask(
      () => ref.read(activityControllerProvider(_key)).load(_date),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access != UserAccess.profileComplete) {
      return Scaffold(
        appBar: AppBar(title: const Text('运动管理')),
        body: _restricted(),
      );
    }
    final controller = ref.watch(activityControllerProvider(_key));
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('运动管理')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              8,
              AppSpacing.page,
              96,
            ),
            children: [
              _dateBar(),
              const SizedBox(height: 12),
              if (state.loading && state.day == null)
                const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.day == null || state.week == null)
                _error(controller, state.error)
              else ...[
                if (state.loading) const LinearProgressIndicator(),
                if (state.stale) _notice('数据可能不是最新，请重新加载'),
                _weekCard(state.week!),
                const SizedBox(height: 12),
                _summary(state.day!),
                const SizedBox(height: 18),
                Text('当天记录', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (state.day!.records.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('当天还没有运动记录，动一动，从今天开始。'),
                    ),
                  )
                else
                  for (final record in state.day!.records)
                    _recordTile(controller, record),
                if (state.saveError != null) ...[
                  const SizedBox(height: 10),
                  _notice(state.saveError!),
                ],
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('activity-add'),
        onPressed: state.saving || _date.isAfter(_today) ? null : _openEditor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        icon: const Icon(Icons.add),
        label: const Text('记录运动'),
      ),
    );
  }

  Widget _restricted() {
    final guest = widget.access == UserAccess.guest;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  guest ? Icons.lock_outline : Icons.assignment_outlined,
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  guest ? '登录后记录运动' : '完善健康档案后记录运动',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  guest ? '登录并完成健康档案，运动记录会安全同步到你的账号。' : '完成档案后即可估算消耗并查看每周运动进度。',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => widget.onProtectedAction('记录运动'),
                  child: Text(guest ? '登录并继续' : '去完善健康档案'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateBar() => Row(
    children: [
      IconButton(
        tooltip: '前一天',
        onPressed: () => _changeDate(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Column(
          children: [
            Text(
              '${_date.month}月${_date.day}日',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (formatLocalDate(_date) != formatLocalDate(_today))
              TextButton(onPressed: _goToday, child: const Text('返回今天')),
          ],
        ),
      ),
      IconButton(
        tooltip: '后一天',
        onPressed: () => _changeDate(1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget _weekCard(ActivityWeek week) {
    final targetDays = week.targetExerciseDays;
    final targetMinutes = week.targetDurationMinutes;
    final status = switch (week.planStatus) {
      ActivityPlanStatus.active =>
        targetDays == null || targetMinutes == null
            ? '本周累计数据'
            : '目标 $targetDays 天 / $targetMinutes 分钟',
      ActivityPlanStatus.noPlan => '生成计划后可查看目标进度',
      ActivityPlanStatus.paused => '计划已暂停，当前仅展示实际数据',
      ActivityPlanStatus.needsRecalculation => '计划需要重新计算，当前仅展示实际数据',
      ActivityPlanStatus.riskBlocked => '当前健康状态不展示普通运动目标',
      ActivityPlanStatus.unknown => '目标状态暂时无法确认',
    };
    final progress = targetMinutes == null || targetMinutes <= 0
        ? 0.0
        : (week.durationMinutes / targetMinutes).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本周进度', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '${week.exerciseDays} 天 · ${week.durationMinutes} 分钟 · ${week.totalKcal} kcal',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(status, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _summary(ActivityDay day) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 28,
        runSpacing: 12,
        children: [
          _metric('运动次数', '${day.recordCount} 次'),
          _metric('累计时长', '${day.totalDurationMinutes} 分钟'),
          _metric('累计消耗', '${day.totalKcal} kcal'),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      Text(label, style: const TextStyle(color: Colors.black54)),
    ],
  );

  Widget _recordTile(
    ActivityController controller,
    ActivityRecord record,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      title: Text(record.activityName),
      subtitle: Text(
        '${record.occurredAt.toLocal().hour.toString().padLeft(2, '0')}:'
        '${record.occurredAt.toLocal().minute.toString().padLeft(2, '0')} · '
        '${record.intensity.label}强度 · ${record.durationMinutes} 分钟 · '
        '${record.finalKcal} kcal${record.calorieSource == CalorieSource.userOverride ? '（已手动修改）' : ''}',
      ),
      onTap: () => _openEditor(record),
      trailing: IconButton(
        tooltip: '删除${record.activityName}',
        onPressed: () => _confirmDelete(controller, record),
        icon: const Icon(Icons.delete_outline),
      ),
    ),
  );

  Widget _error(ActivityController controller, String? error) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 8),
          Text(error ?? '网络连接失败，请稍后重试'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: controller.refresh,
            child: const Text('重新加载'),
          ),
        ],
      ),
    ),
  );

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text),
  );

  void _changeDate(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    ref.read(activityControllerProvider(_key)).load(_date);
  }

  void _goToday() {
    setState(() => _date = _today);
    ref.read(activityControllerProvider(_key)).load(_date);
  }

  Future<void> _openEditor([ActivityRecord? record]) async {
    if (!mounted ||
        (_openedInitialRecord && record == null && widget.openRecordOnStart)) {
      return;
    }
    if (widget.openRecordOnStart && record == null) _openedInitialRecord = true;
    final controller = ref.read(activityControllerProvider(_key));
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ActivityRecordPage(
          controller: controller,
          initialRecord: record,
          selectedDate: _date,
          now: widget.now,
        ),
      ),
    );
    if (changed == true) widget.onChanged?.call();
  }

  Future<void> _confirmDelete(
    ActivityController controller,
    ActivityRecord record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条运动记录？'),
        content: Text('将删除“${record.activityName}”，当天和本周统计会同步更新。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.delete(record.id);
      if (controller.state.saveError == null) widget.onChanged?.call();
    }
  }
}
