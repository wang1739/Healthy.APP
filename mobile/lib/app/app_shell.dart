import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/features/account/presentation/account_page.dart';
import 'package:healthy/features/nutrition/presentation/nutrition_page.dart';
import 'package:healthy/features/hydration/presentation/hydration_page.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/plan/presentation/plan_page.dart';
import 'package:healthy/features/report/presentation/report_page.dart';
import 'package:healthy/features/report/domain/report_data.dart';
import 'package:healthy/features/today/presentation/today_page.dart';
import 'package:healthy/features/activity/presentation/activity_page.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';
import 'package:healthy/features/sleep/presentation/sleep_page.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/presentation/tasks_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.session,
    this.sleepReminderScheduler,
    this.taskNotificationScheduler,
    super.key,
  });

  final SessionController session;
  final SleepReminderScheduler? sleepReminderScheduler;
  final TaskNotificationScheduler? taskNotificationScheduler;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _pinnedKey = 'sidebar_pinned';
  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.today_outlined),
      selectedIcon: Icon(Icons.today),
      label: '今日',
    ),
    NavigationDestination(
      icon: Icon(Icons.restaurant_outlined),
      selectedIcon: Icon(Icons.restaurant),
      label: '饮食',
    ),
    NavigationDestination(
      icon: Icon(Icons.route_outlined),
      selectedIcon: Icon(Icons.route),
      label: '计划',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: '报告',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
    NavigationDestination(
      icon: Icon(Icons.water_drop_outlined),
      selectedIcon: Icon(Icons.water_drop),
      label: '饮水',
    ),
  ];

  int _index = 0;
  bool _hovered = false;
  bool _pinned = false;
  bool _autoPreview = false;
  int _activityRevision = 0;
  int _sleepRevision = 0;
  int _taskRevision = 0;
  String? _reportIntent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    HydrationReminderScheduler.openHydration.addListener(_openHydration);
    SleepReminderScheduler.openSleep.addListener(_openSleepNotification);
    TaskNotificationScheduler.openTask.addListener(_openTaskNotification);
    _syncSleepReminder();
    _syncTaskNotifications();
    if (HydrationReminderScheduler.openHydration.value > 0) _index = 5;
    if (TaskNotificationScheduler.openTask.value != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openTaskNotification(),
      );
    }
    final pending = widget.session.consumePendingFeature();
    if (pending != null) {
      _index = pending.destination;
      _autoPreview = pending.destination == 2;
      if (pending.destination == 3) _reportIntent = pending.label;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (pending.label == '记录运动') {
            _openActivity(record: true);
          } else if (pending.label == '记录睡眠') {
            _openSleep(record: true);
          } else if (pending.label == '创建任务') {
            _openTasks(create: true);
          } else if (pending.label == '添加健康任务') {
            _openTasks();
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('准备完成，可以继续${pending.label}')));
        }
      });
    }
    _loadPinned();
  }

  void _sessionChanged() {
    if (mounted) {
      _syncSleepReminder();
      _syncTaskNotifications();
      setState(() {});
    }
  }

  void _syncSleepReminder() {
    if (widget.session.access != UserAccess.profileComplete) return;
    unawaited(
      (widget.sleepReminderScheduler ?? SleepReminderScheduler.instance).sync(
        widget.session.accountKey,
      ),
    );
  }

  void _syncTaskNotifications() {
    if (widget.session.access == UserAccess.guest) return;
    unawaited(
      (widget.taskNotificationScheduler ?? TaskNotificationScheduler.instance)
          .sync(widget.session.accountKey)
          .catchError((_) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSleepReminder();
      _syncTaskNotifications();
    }
  }

  void _openHydration() {
    if (mounted) setState(() => _index = 5);
  }

  void _openSleepNotification() {
    if (mounted) _openSleep();
  }

  void _openTaskNotification() {
    final target = TaskNotificationScheduler.openTask.value;
    if (mounted && target != null) {
      TaskNotificationScheduler.openTask.value = null;
      _openTasks(date: target.date, instanceId: target.instanceId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    HydrationReminderScheduler.openHydration.removeListener(_openHydration);
    SleepReminderScheduler.openSleep.removeListener(_openSleepNotification);
    TaskNotificationScheduler.openTask.removeListener(_openTaskNotification);
    super.dispose();
  }

  Future<void> _loadPinned() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _pinned = preferences.getBool(_pinnedKey) ?? false);
      }
    } catch (_) {
      // Navigation still works when platform preference storage is unavailable.
    }
  }

  Future<void> _togglePinned() async {
    setState(() => _pinned = !_pinned);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_pinnedKey, _pinned);
    } catch (_) {
      // Keep the current-session preference when persistence is unavailable.
    }
  }

  Future<void> _requestFeature(String label, int destination) async {
    if (widget.session.access == UserAccess.profileComplete) {
      if (widget.session.riskBlocked && label == '生成健康计划') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('暂不生成普通计划'),
            content: const Text('根据你的健康风险评估结果，请先咨询医生或注册营养师。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        return;
      }
      if (label == '记录运动') await _openActivity(record: true);
      if (label == '记录睡眠') await _openSleep(record: true);
      return;
    }

    final guest = widget.session.access == UserAccess.guest;
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                guest ? '登录后开启个性化服务' : '完善健康档案后使用',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                guest
                    ? '登录并完成健康档案后，轻食记才能保存数据并计算适合你的目标。'
                    : '完成健康档案后，轻食记才能计算你的热量、饮水和运动目标。',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(guest ? '登录并继续' : '去完善'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('暂时看看'),
              ),
            ],
          ),
        ),
      ),
    );
    if (proceed == true) {
      widget.session.startRestrictedFlow(
        label: label,
        destination: destination,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(
        api: widget.session.api,
        access: widget.session.access,
        onProtectedAction: (label) => _requestFeature(label, 0),
        onOpenPlan: () => setState(() => _index = 2),
        onOpenNutrition: () => setState(() => _index = 1),
        onOpenHydration: () => setState(() => _index = 5),
        onOpenActivity: () => _openActivity(),
        onRecordActivity: () =>
            widget.session.access == UserAccess.profileComplete
            ? _openActivity(record: true)
            : _requestFeature('记录运动', 0),
        activityRevision: _activityRevision,
        onOpenSleep: () => _openSleep(),
        onRecordSleep: () => widget.session.access == UserAccess.profileComplete
            ? _openSleep(record: true)
            : _requestFeature('记录睡眠', 0),
        sleepRevision: _sleepRevision,
        taskRevision: _taskRevision,
        onOpenTasks: () => _openTasks(),
        onOpenTask: (date, id) => _openTasks(date: date, instanceId: id),
        onCreateTask: () => widget.session.access == UserAccess.guest
            ? _requestFeature('创建任务', 0)
            : _openTasks(create: true),
      ),
      NutritionPage(
        api: widget.session.api,
        access: widget.session.access,
        sessionKey: widget.session.sessionRevision.toString(),
        riskBlocked: widget.session.riskBlocked,
        onProtectedAction: (label) => _requestFeature(label, 1),
        onOpenPlan: () => setState(() => _index = 2),
      ),
      PlanPage(
        api: widget.session.api,
        access: widget.session.access,
        riskBlocked: widget.session.riskBlocked,
        autoPreview: _autoPreview,
        onProtectedAction: (label) => _requestFeature(label, 2),
        onConfirmed: () => setState(() => _index = 0),
        onEditProfile: widget.session.openProfile,
      ),
      ReportPage(
        api: widget.session.api,
        access: widget.session.access,
        accountKey: widget.session.accountKey,
        onProtectedAction: (label) => _requestFeature(label, 3),
        onOpenSource: _openReportSource,
        initialIntent: _reportIntent,
        onIntentHandled: () => _reportIntent = null,
        active: _index == 3,
      ),
      AccountPage(session: widget.session),
      HydrationPage(
        api: widget.session.api,
        access: widget.session.access,
        sessionKey: widget.session.sessionRevision.toString(),
        onProtectedAction: (label) => _requestFeature(label, 5),
      ),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = IndexedStack(index: _index, children: pages);

    if (wide) {
      final expanded = _hovered || _pinned;
      return Scaffold(
        body: Row(
          children: [
            MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: NavigationRail(
                extended: expanded,
                selectedIndex: _index,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: expanded
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _BrandMark(),
                            const SizedBox(width: 10),
                            const Text(
                              '轻食记',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            IconButton(
                              tooltip: _pinned ? '取消固定' : '固定侧栏',
                              onPressed: _togglePinned,
                              icon: Icon(
                                _pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                              ),
                            ),
                          ],
                        )
                      : const _BrandMark(),
                ),
                destinations: _destinations
                    .map(
                      (item) => NavigationRailDestination(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          height: 62,
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: _destinations,
        ),
      ),
    );
  }

  Future<void> _openActivity({bool record = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ActivityPage(
          api: widget.session.api,
          access: widget.session.access,
          sessionKey: widget.session.sessionRevision.toString(),
          onProtectedAction: (label) => _requestFeature(label, 0),
          openRecordOnStart: record,
          onChanged: () => setState(() => _activityRevision++),
        ),
      ),
    );
  }

  Future<void> _openSleep({bool record = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SleepPage(
          api: widget.session.api,
          access: widget.session.access,
          sessionKey: widget.session.accountKey,
          onProtectedAction: (label) => _requestFeature(label, 0),
          openRecordOnStart: record,
          onChanged: () => setState(() => _sleepRevision++),
          reminderScheduler: widget.sleepReminderScheduler,
        ),
      ),
    );
  }

  Future<void> _openTasks({
    bool create = false,
    DateTime? date,
    String? instanceId,
  }) async {
    if (widget.session.access == UserAccess.guest &&
        (create || instanceId != null)) {
      await _requestFeature(create ? '创建任务' : '查看每日任务', 0);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TasksPage(
          api: widget.session.api,
          access: widget.session.access,
          accountKey: widget.session.accountKey,
          onProtectedAction: (label) => _requestFeature(label, 0),
          onHealthTaskRequested: (label) {
            if (widget.session.access == UserAccess.profileIncomplete) {
              _requestFeature('添加健康任务', 0);
            } else {
              setState(() => _index = 2);
              Navigator.pop(context);
            }
          },
          initialDate: date,
          initialInstanceId: instanceId,
          openEditorOnStart: create,
          notificationScheduler: widget.taskNotificationScheduler,
          onChanged: () => setState(() => _taskRevision++),
        ),
      ),
    );
  }

  void _openReportSource(ReportSource source) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (source.sourceType) {
      case 'PLAN_VERSION':
      case 'WEIGHT_MEASUREMENT':
        setState(() => _index = 2);
      case 'MEAL_ENTRY':
        setState(() => _index = 1);
      case 'HYDRATION_ENTRY':
        setState(() => _index = 5);
      case 'ACTIVITY_RECORD':
        _openActivity();
      case 'SLEEP_RECORD':
        _openSleep();
      case 'TASK_INSTANCE':
        _openTasks(date: source.localDate, instanceId: source.sourceId);
      default:
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('原始记录已删除')));
    }
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '轻',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}
