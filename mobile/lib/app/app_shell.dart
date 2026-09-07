import 'package:flutter/material.dart';
import 'package:healthy/features/account/presentation/account_page.dart';
import 'package:healthy/features/nutrition/presentation/nutrition_page.dart';
import 'package:healthy/features/plan/presentation/plan_page.dart';
import 'package:healthy/features/report/presentation/report_page.dart';
import 'package:healthy/features/today/presentation/today_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _pinnedKey = 'sidebar_pinned';
  static const _pages = [
    TodayPage(),
    NutritionPage(),
    PlanPage(),
    ReportPage(),
    AccountPage(),
  ];
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
  ];

  int _index = 0;
  bool _hovered = false;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _loadPinned();
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

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = IndexedStack(index: _index, children: _pages);

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
