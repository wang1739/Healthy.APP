import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/features/account/presentation/account_page.dart';
import 'package:healthy/features/nutrition/presentation/nutrition_page.dart';
import 'package:healthy/features/hydration/presentation/hydration_page.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/plan/presentation/plan_page.dart';
import 'package:healthy/features/report/presentation/report_page.dart';
import 'package:healthy/features/today/presentation/today_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.session, super.key});

  final SessionController session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
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

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    HydrationReminderScheduler.openHydration.addListener(_openHydration);
    if (HydrationReminderScheduler.openHydration.value > 0) _index = 5;
    final pending = widget.session.consumePendingFeature();
    if (pending != null) {
      _index = pending.destination;
      _autoPreview = pending.destination == 2;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('准备完成，可以继续${pending.label}')));
        }
      });
    }
    _loadPinned();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  void _openHydration() {
    if (mounted) setState(() => _index = 5);
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    HydrationReminderScheduler.openHydration.removeListener(_openHydration);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            label.startsWith('记录') ? '该记录功能将在后续阶段接入' : '$label功能将在下一阶段接入',
          ),
        ),
      );
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
      ReportPage(onProtectedAction: (label) => _requestFeature(label, 3)),
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
