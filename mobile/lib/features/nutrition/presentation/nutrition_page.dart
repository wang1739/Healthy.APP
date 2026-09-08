import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/nutrition/application/nutrition_controller.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/nutrition/presentation/food_entry_sheet.dart';
import 'package:healthy/features/nutrition/presentation/meal_section.dart';
import 'package:healthy/features/nutrition/presentation/nutrition_summary.dart';

class NutritionPage extends ConsumerStatefulWidget {
  const NutritionPage({
    required this.api,
    required this.access,
    required this.sessionKey,
    required this.onProtectedAction,
    required this.onOpenPlan,
    this.initialDate,
    this.now,
    this.riskBlocked = false,
    super.key,
  });

  final ApiClient api;
  final UserAccess access;
  final String sessionKey;
  final ValueChanged<String> onProtectedAction;
  final VoidCallback onOpenPlan;
  final DateTime? initialDate;
  final DateTime Function()? now;
  final bool riskBlocked;

  @override
  ConsumerState<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends ConsumerState<NutritionPage>
    with WidgetsBindingObserver {
  late DateTime _date;
  late NutritionProviderKey _key;

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
    _setKey();
    _load();
  }

  void _setKey() {
    _key = NutritionProviderKey(
      widget.api,
      widget.sessionKey,
      _date,
      today: _today,
    );
  }

  @override
  void didUpdateWidget(covariant NutritionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionKey != widget.sessionKey ||
        oldWidget.access != widget.access) {
      _setKey();
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _date == _today) return;
    setState(() {
      _date = _today;
    });
    _load();
  }

  void _load() {
    if (widget.access != UserAccess.profileComplete) return;
    Future.microtask(
      () => ref.read(nutritionControllerProvider(_key)).load(_date),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access == UserAccess.guest) return _restricted(true);
    if (widget.access == UserAccess.profileIncomplete) {
      return _restricted(false);
    }
    final controller = ref.watch(nutritionControllerProvider(_key));
    final state = controller.state;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.page,
              96,
            ),
            children: [
              Text('饮食记录', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              _dateBar(),
              const SizedBox(height: 12),
              if (state.loading && state.data == null)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.data == null)
                _error(controller, state.error)
              else ...[
                if (state.loading) const LinearProgressIndicator(),
                if (state.stale) _notice('数据可能不是最新，请重新加载'),
                if (state.futureDate) _notice('未来日期仅可查看'),
                if (widget.riskBlocked ||
                    state.data!.status == NutritionDayStatus.riskBlocked)
                  _notice('当前健康状态不展示普通减脂目标，请咨询专业人士。'),
                NutritionSummary(
                  summary: state.data!.summary,
                  target:
                      widget.riskBlocked ||
                          state.data!.status == NutritionDayStatus.riskBlocked
                      ? null
                      : state.data!.target,
                  onOpenPlan: widget.onOpenPlan,
                ),
                if (state.data!.summary.calories == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('记录第一餐，看看今天的营养进度'),
                  ),
                for (final meal in state.data!.meals)
                  MealSection(
                    meal: meal,
                    readOnly: state.futureDate,
                    onAdd: () => _openEditor(controller, meal.type),
                    onEdit: (entry) =>
                        _openEditor(controller, meal.type, entry),
                    onDelete: (entry) => _confirmDelete(controller, entry),
                  ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: state.data != null && !state.futureDate
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(controller, _recommendedMeal()),
              icon: const Icon(Icons.add),
              label: const Text('添加食物'),
            )
          : null,
    );
  }

  Widget _restricted(bool guest) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Text('饮食记录', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
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
                  guest ? '登录后记录每一餐' : '完善健康档案后开始记录',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  guest
                      ? '登录并完成健康档案，饮食记录会安全同步到你的账号。'
                      : '完成档案后即可记录饮食，即使还没有减脂计划也能使用。',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => widget.onProtectedAction('记录饮食'),
                  child: Text(guest ? '开始记录' : '去完善健康档案'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

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
            if (_date != _today)
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

  void _changeDate(int days) {
    setState(() {
      _date = _date.add(Duration(days: days));
    });
    _load();
  }

  void _goToday() {
    setState(() {
      _date = _today;
    });
    _load();
  }

  Widget _error(NutritionController controller, String? error) => Card(
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

  MealType _recommendedMeal() {
    final now = widget.now?.call() ?? DateTime.now();
    final minute = now.hour * 60 + now.minute;
    if (minute >= 300 && minute < 630) return MealType.breakfast;
    if (minute >= 630 && minute < 870) return MealType.lunch;
    if (minute >= 1050) return MealType.dinner;
    return MealType.snack;
  }

  Future<void> _openEditor(
    NutritionController controller,
    MealType meal, [
    MealEntry? entry,
  ]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (sheetContext) => FoodEntrySheet(
        api: widget.api,
        initialMeal: meal,
        initialEntry: entry,
        onSave: (payload) async {
          if (entry == null) {
            await controller.add(payload);
          } else {
            await controller.update(entry.id, payload);
          }
          if (controller.state.saveError != null) {
            throw FormatException(controller.state.saveError!);
          }
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    NutritionController controller,
    MealEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('将删除“${entry.foodName}”，全天营养会同步更新。'),
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
    if (confirmed == true) await controller.delete(entry.id);
  }
}
