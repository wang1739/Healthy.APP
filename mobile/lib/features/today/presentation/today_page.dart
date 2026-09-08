import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_colors.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/plan/application/plan_controller.dart';
import 'package:healthy/features/today/application/today_controller.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:healthy/features/today/presentation/today_carousel.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({
    required this.api,
    required this.access,
    required this.onProtectedAction,
    required this.onOpenPlan,
    super.key,
  });

  final ApiClient api;
  final UserAccess access;
  final ValueChanged<String> onProtectedAction;
  final VoidCallback onOpenPlan;

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage>
    with WidgetsBindingObserver {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _date = _today();
    _loadPrivateData();
  }

  @override
  void didUpdateWidget(covariant TodayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.access != widget.access || oldWidget.api != widget.api) {
      _loadPrivateData();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final today = _today();
    if (formatLocalDate(today) == formatLocalDate(_date)) return;
    setState(() => _date = today);
    _loadPrivateData();
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _loadPrivateData() {
    if (widget.access != UserAccess.profileComplete) return;
    Future.microtask(
      () => ref.read(todayControllerProvider(widget.api)).load(_date),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      _header(),
      const SizedBox(height: AppSpacing.medium),
      const TodayCarousel(),
      const SizedBox(height: AppSpacing.large),
    ];

    if (widget.access == UserAccess.guest) {
      content.addAll(_guest());
    } else if (widget.access == UserAccess.profileIncomplete) {
      content.addAll(_incomplete());
    } else {
      content.addAll(_privateContent());
    }
    content.addAll([
      const SizedBox(height: AppSpacing.large),
      _quickActions(),
      const SizedBox(height: AppSpacing.large),
    ]);

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.page),
      children: content,
    );
    if (widget.access != UserAccess.profileComplete) {
      return SafeArea(child: list);
    }
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: ref.read(todayControllerProvider(widget.api)).refresh,
        child: list,
      ),
    );
  }

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_greeting(), style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      const Text('今日概览'),
      Text(
        '${_date.month}月${_date.day}日 · 星期${const ['一', '二', '三', '四', '五', '六', '日'][_date.weekday - 1]}',
        style: const TextStyle(color: Colors.black54),
      ),
    ],
  );

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return '早上好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  List<Widget> _guest() => [
    _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '登录后开启你的今日计划',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('登录并完成健康档案后，这里会展示真实的计划目标和最新体重。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => widget.onProtectedAction('查看个性化今日目标'),
            child: const Text('登录并开始'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _incomplete() => [
    _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '完善健康档案',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('完成档案后，轻食记才能安全地生成并展示你的今日目标。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => widget.onProtectedAction('完善健康档案'),
            child: const Text('完善健康档案'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _privateContent() {
    final controller = ref.watch(todayControllerProvider(widget.api));
    final state = controller.state;
    if (state.data == null && state.loading) {
      return [
        const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (state.data == null) {
      return [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
              Text(state.error ?? '网络连接失败，请稍后重试', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => controller.load(_date),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ];
    }

    final data = state.data!;
    final preview = ref.watch(planControllerProvider(widget.api)).state.data;
    final hasPreview = preview?.kind == PlanKind.preview;
    return [
      if (state.loading) const LinearProgressIndicator(),
      if (state.stale) ...[
        _notice('刷新失败，当前内容可能不是最新'),
        const SizedBox(height: 12),
      ],
      _planCard(data.plan),
      if (data.plan.state != 'RISK_BLOCKED') ...[
        const SizedBox(height: AppSpacing.medium),
        Text('今日执行', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        _executionGrid(data),
      ],
      const SizedBox(height: AppSpacing.medium),
      _nextAction(data, hasPreview),
    ];
  }

  Widget _planCard(TodayPlanData plan) {
    if (plan.status == TodayModuleStatus.error) {
      return _card(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日核心目标', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('该项数据暂时无法加载'),
          ],
        ),
      );
    }
    if (plan.status == TodayModuleStatus.empty) {
      return _card(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日核心目标', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('生成计划后，这里会显示你的每日目标'),
          ],
        ),
      );
    }
    if (plan.state == 'RISK_BLOCKED') {
      return _card(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('健康建议', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('当前情况不展示普通减脂目标，请咨询医生或注册营养师。'),
          ],
        ),
      );
    }

    final stateText = switch (plan.state) {
      'PAUSED' => '计划已暂停',
      'NEEDS_RECALCULATION' => '计划需要重新计算',
      _ => '计划执行中',
    };
    return Semantics(
      button: true,
      label: '今日核心目标，点击查看计划',
      child: Card(
        color: AppColors.green,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onOpenPlan,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stateText,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${plan.targetKcal ?? '-'} kcal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text('每日目标热量', style: TextStyle(color: Colors.white)),
                  ],
                ),
                Text(
                  plan.currentWeek == null ? '' : '第 ${plan.currentWeek} 周',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _executionGrid(TodayData data) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720
          ? 3
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      final cards = [
        _moduleCard(
          '饮食',
          data.plan.targetKcal == null ? null : '${data.plan.targetKcal} kcal',
          data.plan.status == TodayModuleStatus.error
              ? TodayModuleStatus.error
              : data.nutrition.status,
          Icons.restaurant_outlined,
          data.nutrition.message,
        ),
        _moduleCard(
          '饮水',
          data.plan.waterMl == null ? null : '${data.plan.waterMl} ml',
          data.hydration.status,
          Icons.water_drop_outlined,
          data.hydration.message,
        ),
        _moduleCard(
          '运动',
          data.plan.exerciseDays == null
              ? null
              : '${data.plan.exerciseDays} 天 / ${data.plan.exerciseMinutes} 分钟',
          data.activity.status,
          Icons.directions_run,
          data.activity.message,
        ),
        _moduleCard(
          '睡眠',
          data.plan.sleepHours == null
              ? null
              : '${data.plan.sleepHours!.toStringAsFixed(1)} 小时',
          data.sleep.status,
          Icons.bedtime_outlined,
          data.sleep.message,
        ),
        _moduleCard(
          '体重',
          data.weight.valueKg == null
              ? null
              : '${data.weight.valueKg!.toStringAsFixed(1)} kg',
          data.weight.status,
          Icons.monitor_weight_outlined,
          data.weight.message,
          emptyText: '暂无最新体重',
        ),
        _moduleCard(
          '营养',
          data.plan.proteinG == null ||
                  data.plan.carbsG == null ||
                  data.plan.fatG == null
              ? null
              : '蛋白质 ${data.plan.proteinG} g · 碳水 ${data.plan.carbsG} g · 脂肪 ${data.plan.fatG} g',
          data.plan.status,
          Icons.egg_alt_outlined,
          data.plan.message,
        ),
      ];
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: cards
            .map((card) => SizedBox(width: width, child: card))
            .toList(),
      );
    },
  );

  Widget _moduleCard(
    String title,
    String? value,
    TodayModuleStatus status,
    IconData icon,
    String? message, {
    String emptyText = '今日暂无数据',
  }) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 4),
        Text(switch (status) {
          TodayModuleStatus.comingSoon => message ?? '记录功能待接入',
          TodayModuleStatus.empty => emptyText,
          TodayModuleStatus.error => message ?? '该项数据暂时无法加载',
          TodayModuleStatus.ready => '数据已更新',
        }, style: const TextStyle(color: Colors.black54)),
      ],
    ),
  );

  Widget _nextAction(TodayData data, bool hasPreview) {
    final title = hasPreview ? '继续确认计划' : data.nextAction.title;
    final type = hasPreview
        ? TodayNextActionType.confirmPlan
        : data.nextAction.type;
    if (data.plan.state == 'NEEDS_RECALCULATION' && !hasPreview) {
      return _actionCard('下一步建议', '计划需要重新计算', widget.onOpenPlan);
    }
    return _actionCard('下一步建议', title, () => _runAction(type));
  }

  Widget _actionCard(String label, String title, VoidCallback action) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        FilledButton(onPressed: action, child: Text(title)),
      ],
    ),
  );

  void _runAction(TodayNextActionType type) {
    switch (type) {
      case TodayNextActionType.completeProfile:
        widget.onProtectedAction('完善健康档案');
      case TodayNextActionType.createPlan:
      case TodayNextActionType.confirmPlan:
      case TodayNextActionType.resumePlan:
      case TodayNextActionType.viewPlan:
        widget.onOpenPlan();
      case TodayNextActionType.viewRiskGuidance:
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('健康建议'),
            content: const Text('当前情况不适合普通减脂计划，请咨询医生或注册营养师。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
      case TodayNextActionType.unknown:
        widget.onOpenPlan();
    }
  }

  Widget _quickActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('快捷操作', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _quickButton('记录饮食', Icons.restaurant_outlined),
          _quickButton('记录饮水', Icons.water_drop_outlined),
          _quickButton('记录运动', Icons.directions_run),
          _quickButton('记录睡眠', Icons.bedtime_outlined),
        ],
      ),
    ],
  );

  Widget _quickButton(String label, IconData icon) => OutlinedButton.icon(
    onPressed: () => widget.onProtectedAction(label),
    icon: Icon(icon),
    label: Text(label),
  );

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text),
  );

  Widget _card({required Widget child}) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}
