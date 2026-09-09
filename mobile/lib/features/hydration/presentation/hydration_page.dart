import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/hydration/application/hydration_controller.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:healthy/features/hydration/presentation/hydration_progress.dart';
import 'package:healthy/features/hydration/presentation/hydration_settings_sheet.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class HydrationPage extends ConsumerStatefulWidget {
  const HydrationPage({
    required this.api,
    required this.access,
    required this.sessionKey,
    required this.onProtectedAction,
    this.now,
    super.key,
  });
  final ApiClient api;
  final UserAccess access;
  final String sessionKey;
  final ValueChanged<String> onProtectedAction;
  final DateTime Function()? now;
  @override
  ConsumerState<HydrationPage> createState() => _State();
}

class _State extends ConsumerState<HydrationPage> with WidgetsBindingObserver {
  late DateTime date;
  DateTime get today {
    final n = widget.now?.call() ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  HydrationProviderKey get key =>
      HydrationProviderKey(widget.api, widget.sessionKey, today, today: today);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    date = today;
    if (widget.access == UserAccess.profileComplete) {
      Future.microtask(
        () => ref.read(hydrationControllerProvider(key)).load(date),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || date == today) return;
    setState(() => date = today);
    if (widget.access == UserAccess.profileComplete) {
      Future.microtask(
        () =>
            ref.read(hydrationControllerProvider(key)).load(date, force: true),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void move(int days) {
    setState(() => date = date.add(Duration(days: days)));
    if (widget.access == UserAccess.profileComplete) {
      Future.microtask(
        () => ref.read(hydrationControllerProvider(key)).load(date),
      );
    }
  }

  void protected(VoidCallback action) {
    if (widget.access == UserAccess.profileComplete) {
      action();
    } else {
      widget.onProtectedAction(
        widget.access == UserAccess.guest ? '登录后记录饮水' : '完善档案后记录饮水',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.access == UserAccess.profileComplete
        ? ref.watch(hydrationControllerProvider(key)).state
        : null;
    final day =
        state?.data ??
        HydrationDay.fromJson({
          'date': formatLocalDate(date),
          'status': 'EMPTY',
          'consumedMl': 0,
          'targetMl': 2000,
          'remainingMl': 2000,
          'progress': 0,
          'targetSource': 'DEFAULT',
          'settings': {
            'defaultCupMl': 250,
            'effectiveTargetMl': 2000,
            'reminderEnabled': false,
            'version': 0,
          },
          'entries': [],
        });
    final c = widget.access == UserAccess.profileComplete
        ? ref.read(hydrationControllerProvider(key))
        : null;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => c?.refresh() ?? Future.value(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '饮水记录',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: '饮水设置',
                  onPressed: () => protected(
                    () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                      builder: (_) => HydrationSettingsSheet(
                        settings: day.settings,
                        onSave: (v) async {
                          if (v['reminderEnabled'] == true) {
                            final allowed = await HydrationReminderScheduler
                                .instance
                                .requestPermission();
                            if (!allowed) {
                              v['reminderEnabled'] = false;
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('通知权限未开启，饮水记录仍可正常使用'),
                                  ),
                                );
                              }
                            }
                          }
                          c!.setSettingsDraft(v);
                          await c.saveSettings();
                        },
                        onAdoptPlan: () async {
                          await widget.api.adoptPlanHydrationTarget();
                          await c!.refresh();
                        },
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: '前一天',
                  onPressed: () => move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${date.month}月${date.day}日'),
                IconButton(
                  tooltip: '后一天',
                  onPressed: date.isBefore(today) ? () => move(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (date != today)
              TextButton(
                onPressed: () => move(today.difference(date).inDays),
                child: const Text('返回今天'),
              ),
            HydrationProgress(day: day),
            if (widget.access != UserAccess.profileComplete)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  widget.access == UserAccess.guest ? '登录后记录饮水' : '完善档案后记录饮水',
                ),
              ),
            if (state?.stale == true) const Text('数据可能不是最新'),
            if (state?.error != null) ...[
              Text(state!.error!),
              TextButton(onPressed: c!.refresh, child: const Text('重新加载')),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  protected(() => c!.add(day.settings.defaultCupMl)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text('+${day.settings.defaultCupMl} ml'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in [100, 200, 250, 300, 500])
                  OutlinedButton(
                    onPressed: () =>
                        protected(() => c!.add(amount, source: 'PRESET')),
                    child: Text('$amount ml'),
                  ),
                OutlinedButton(
                  onPressed: () => protected(() => _custom(c!)),
                  child: const Text('自定义'),
                ),
              ],
            ),
            if (state?.saveError != null) ...[
              Text(
                state!.saveError!,
                style: const TextStyle(color: Colors.red),
              ),
              if (state.retryAmountMl != null)
                TextButton(onPressed: c!.retry, child: const Text('重新添加')),
            ],
            const SizedBox(height: 20),
            Text('当日记录', style: Theme.of(context).textTheme.titleLarge),
            if (day.entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('今天还没有饮水记录')),
              ),
            for (final e in day.entries)
              ListTile(
                title: Text('${e.amountMl} ml'),
                subtitle: Text(
                  TimeOfDay.fromDateTime(e.occurredAt.toLocal())
                      .format(context),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(c!, e),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _custom(HydrationController c) async {
    var input = '';
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义容量'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => input = value,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '1–3000 ml'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(input);
              if (value == null || value < 1 || value > 3000) {
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(const SnackBar(content: Text('请输入 1–3000 ml')));
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (amount != null && mounted) {
      await c.add(amount, source: 'CUSTOM');
    }
  }

  Future<void> _delete(HydrationController c, HydrationEntry e) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除饮水记录？'),
        content: Text('确定删除 ${e.amountMl} ml 记录吗？'),
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
    if (yes == true) await c.delete(e.id);
  }
}
