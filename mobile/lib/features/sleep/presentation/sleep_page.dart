import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/sleep/application/sleep_controller.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:healthy/features/sleep/presentation/sleep_record_page.dart';
import 'package:healthy/features/sleep/presentation/sleep_reminder_sheet.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class SleepPage extends ConsumerStatefulWidget {
  const SleepPage({
    required this.api,
    required this.access,
    required this.sessionKey,
    required this.onProtectedAction,
    this.onChanged,
    this.openRecordOnStart = false,
    this.initialDate,
    this.now,
    this.reminderScheduler,
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
  final SleepReminderScheduler? reminderScheduler;
  @override
  ConsumerState<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends ConsumerState<SleepPage>
    with WidgetsBindingObserver {
  late DateTime _date;
  late SleepProviderKey _key;
  bool _opened = false;
  DateTime get _today {
    final value = widget.now?.call() ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = widget.initialDate ?? _today;
    _date = DateTime(initial.year, initial.month, initial.day);
    _key = SleepProviderKey(
      widget.api,
      widget.sessionKey,
      _date,
      now: widget.now?.call(),
    );
    _load();
    if (widget.access == UserAccess.profileComplete) {
      Future.microtask(
        () => (widget.reminderScheduler ?? SleepReminderScheduler.instance)
            .sync(widget.sessionKey),
      );
    }
    if (widget.openRecordOnStart &&
        widget.access == UserAccess.profileComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditor());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.access == UserAccess.profileComplete) {
      (widget.reminderScheduler ?? SleepReminderScheduler.instance).sync(
        widget.sessionKey,
      );
    }
  }

  void _load() {
    if (widget.access == UserAccess.profileComplete) {
      Future.microtask(
        () => ref.read(sleepControllerProvider(_key)).load(_date),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access != UserAccess.profileComplete) {
      return Scaffold(
        appBar: AppBar(title: const Text('睡眠管理')),
        body: _restricted(),
      );
    }
    final controller = ref.watch(sleepControllerProvider(_key));
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('睡眠管理'),
        actions: [
          IconButton(
            tooltip: '睡前提醒',
            onPressed: _openReminder,
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
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
                _nightCard(state.day!),
                const SizedBox(height: 12),
                _weekSummary(state.week!),
                const SizedBox(height: 12),
                _bars(state.week!),
                const SizedBox(height: 18),
                Text('当天记录', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (state.day!.records.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('当天还没有睡眠记录。'),
                    ),
                  )
                else
                  for (final record in state.day!.records)
                    _recordTile(controller, record),
                if (state.saveError != null) _notice(state.saveError!),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('sleep-add'),
        onPressed: _date.isAfter(_today) || state.saving ? null : _openEditor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        icon: const Icon(Icons.add),
        label: const Text('记录睡眠'),
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
                  guest ? '登录后记录睡眠' : '完善健康档案后记录睡眠',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  guest
                      ? '登录并完成健康档案，睡眠记录会安全同步到你的账号。'
                      : '完成档案后即可记录睡眠并查看最近 7 天汇总。',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => widget.onProtectedAction('记录睡眠'),
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

  Widget _nightCard(SleepDay day) {
    final night = day.night;
    final target = day.targetMinutes;
    final difference = target == null
        ? null
        : day.nightDurationMinutes - target;
    final status = switch (day.planStatus) {
      SleepPlanStatus.active =>
        difference == null
            ? '睡眠目标可执行'
            : difference >= 0
            ? '已达到目标，多 $difference 分钟'
            : '距目标还差 ${-difference} 分钟',
      SleepPlanStatus.noPlan => '生成计划后可查看目标进度',
      SleepPlanStatus.paused => '计划已暂停，当前仅展示实际数据',
      SleepPlanStatus.needsRecalculation => '计划需要重新计算',
      SleepPlanStatus.riskBlocked => '当前健康状态不展示普通睡眠目标',
      SleepPlanStatus.unknown => '目标状态暂时无法确认',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('昨晚睡眠', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              _durationText(day.nightDurationMinutes),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            Text(night == null ? '未评价' : sleepQualityLabel(night.qualityScore)),
            const SizedBox(height: 6),
            Text(status, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _weekSummary(SleepWeek week) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('最近 7 天', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _metric('平均夜间睡眠', _durationText(week.averageNightMinutes)),
              _metric(
                '目标达标',
                week.targetMinutes == null
                    ? '暂无目标'
                    : '${week.targetAchievedDays} 天',
              ),
              _metric(
                '平均质量',
                week.averageQuality == null
                    ? '未评价'
                    : week.averageQuality!.toStringAsFixed(1),
              ),
              _metric('小睡总时长', '${week.napTotalMinutes} 分钟'),
            ],
          ),
          if (!week.hasEnoughTrendData)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '记录不足，继续记录后可查看趋势',
                style: TextStyle(color: Colors.black54),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _bars(SleepWeek week) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日夜间时长', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final point in week.dailyPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text('${point.date.month}/${point.date.day}'),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (point.nightMinutes / 960).clamp(0, 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${point.nightMinutes} 分'),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(color: Colors.black54)),
    ],
  );
  String _durationText(int minutes) =>
      minutes < 60 ? '$minutes 分钟' : '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';

  Widget _recordTile(SleepController controller, SleepRecord record) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      title: Text(record.type.label),
      subtitle: Text(
        '${_durationText(record.durationMinutes)} · ${sleepQualityLabel(record.qualityScore)}',
      ),
      onTap: () => _openEditor(record),
      trailing: IconButton(
        tooltip: '删除${record.type.label}',
        onPressed: () => _confirmDelete(controller, record),
        icon: const Icon(Icons.delete_outline),
      ),
    ),
  );

  Widget _error(SleepController controller, String? error) => Card(
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
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text),
  );

  void _changeDate(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    ref.read(sleepControllerProvider(_key)).load(_date);
  }

  void _goToday() {
    setState(() => _date = _today);
    ref.read(sleepControllerProvider(_key)).load(_date);
  }

  Future<void> _openEditor([SleepRecord? record]) async {
    if (!mounted || (_opened && record == null && widget.openRecordOnStart)) {
      return;
    }
    if (widget.openRecordOnStart && record == null) _opened = true;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SleepRecordPage(
          controller: ref.read(sleepControllerProvider(_key)),
          selectedDate: _date,
          initialRecord: record,
          now: widget.now,
        ),
      ),
    );
    if (changed == true) widget.onChanged?.call();
  }

  Future<void> _openReminder() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
    ),
    builder: (_) => SleepReminderSheet(
      accountKey: widget.sessionKey,
      scheduler: widget.reminderScheduler ?? SleepReminderScheduler.instance,
    ),
  );

  Future<void> _confirmDelete(
    SleepController controller,
    SleepRecord record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条睡眠记录？'),
        content: const Text('删除后，当天和最近 7 天统计会同步更新。'),
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
