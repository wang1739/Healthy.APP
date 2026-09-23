import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_colors.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/plan/application/plan_controller.dart';

class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({
    required this.api,
    required this.access,
    required this.riskBlocked,
    required this.onProtectedAction,
    required this.onConfirmed,
    required this.onEditProfile,
    this.autoPreview = false,
    this.sessionRevision = 0,
    super.key,
  });

  final ApiClient api;
  final UserAccess access;
  final bool riskBlocked;
  final ValueChanged<String> onProtectedAction;
  final VoidCallback onConfirmed;
  final VoidCallback onEditProfile;
  final bool autoPreview;
  final int sessionRevision;

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  Map<String, dynamic>? _previewAdjustments;

  @override
  void initState() {
    super.initState();
    if (widget.access == UserAccess.profileComplete && !widget.riskBlocked) {
      Future.microtask(
        () => ref
            .read(planControllerProvider(widget.api))
            .load(autoPreview: widget.autoPreview),
      );
    }
  }

  @override
  void didUpdateWidget(covariant PlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionRevision != widget.sessionRevision) {
      _previewAdjustments = null;
    }
    final becameAvailable =
        widget.access == UserAccess.profileComplete &&
        !widget.riskBlocked &&
        (oldWidget.access != UserAccess.profileComplete ||
            oldWidget.riskBlocked);
    if (becameAvailable) {
      Future.microtask(
        () => ref.read(planControllerProvider(widget.api)).load(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access != UserAccess.profileComplete) return _example();
    if (widget.riskBlocked) return _risk();

    final controller = ref.watch(planControllerProvider(widget.api));
    final state = controller.state;
    final data = state.data;
    if (data == null && state.loading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    if (data == null) return _networkFailure(controller);

    return PopScope<void>(
      canPop: data.kind != PlanKind.preview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && data.kind == PlanKind.preview) {
          if (state.recalculationPreview) {
            _cancelRecalculation(controller);
          } else {
            _reload(controller);
          }
        }
      },
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _reload(controller),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '减脂计划',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新计划',
                    onPressed: state.loading ? null : () => _reload(controller),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (state.error != null) ...[
                const SizedBox(height: AppSpacing.small),
                _errorBanner(controller),
              ],
              const SizedBox(height: AppSpacing.medium),
              if (data.kind == PlanKind.noPlan)
                _empty(controller)
              else if (data.kind == PlanKind.risk)
                _risk(message: data.message)
              else if (data.kind == PlanKind.unsupported)
                _unsupported(data)
              else
                _plan(data, controller, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _example() => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Text('减脂计划', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.medium),
        _card(
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('示例', style: TextStyle(color: AppColors.green)),
              SizedBox(height: 8),
              Text('登录并完成健康档案后，为你生成安全、可解释的四周减脂计划。'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.medium),
        FilledButton(
          onPressed: () => widget.onProtectedAction('生成减脂计划'),
          child: const Text('生成减脂计划'),
        ),
      ],
    ),
  );

  Widget _networkFailure(PlanController controller) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 54),
            const SizedBox(height: 16),
            const Text('暂时无法更新', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('网络连接失败，请稍后重试'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => _reload(controller),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _errorBanner(PlanController controller) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            controller.state.error == null ||
                    controller.state.error!.startsWith('网络连接失败')
                ? '暂时无法更新，正在显示上次加载的计划'
                : controller.state.error!,
          ),
        ),
        TextButton(
          onPressed: () => _reload(controller),
          child: const Text('重试'),
        ),
      ],
    ),
  );

  Widget _empty(PlanController controller) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.route_outlined, color: AppColors.green, size: 44),
        const SizedBox(height: 12),
        const Text(
          '还没有减脂计划',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text('根据你的档案生成每日热量、营养、饮水、运动和睡眠目标。', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: controller.state.loading
              ? null
              : () => _generate(controller),
          child: const Text('生成减脂计划'),
        ),
      ],
    ),
  );

  Widget _risk({String? message}) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: _card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.health_and_safety_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                '暂不生成普通减脂计划',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(message ?? '根据健康风险评估结果，请先咨询医生或注册营养师。'),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: widget.onEditProfile,
                child: const Text('返回修改档案'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _unsupported(PlanData data) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('当前目标计划尚未开放', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(data.message ?? '本阶段仅支持减脂计划。'),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: widget.onEditProfile,
          child: const Text('修改健康目标'),
        ),
      ],
    ),
  );

  Widget _plan(PlanData data, PlanController controller, PlanViewState state) {
    final loading = state.loading;
    final useStackedLayout =
        MediaQuery.sizeOf(context).width <= 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = state.recalculationPreview
        ? '新计划预览'
        : data.kind == PlanKind.preview
        ? '计划预览'
        : data.kind == PlanKind.paused
        ? '已暂停'
        : data.needsRecalculation
        ? '需要重新计算'
        : '执行中';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          children: [
            _statusChip(title),
            if (data.kind != PlanKind.preview)
              Text('第 ${data.currentWeek} 周 · 版本 ${data.version}'),
          ],
        ),
        if (data.needsRecalculation) ...[
          const SizedBox(height: 12),
          _notice('健康档案已变化，旧计划可能不再匹配，请确认后重新计算。'),
        ],
        if (state.recalculationPreview && state.previous != null) ...[
          const SizedBox(height: 12),
          _changes(state.previous!, data),
        ],
        if (data.kind == PlanKind.paused) ...[
          const SizedBox(height: 12),
          _notice(
            '计划已暂停${data.pausedAt == null ? '' : '（${_date(data.pausedAt!)}）'}，今日页不再提供执行目标。',
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(6),
          ),
          child: useStackedLayout
              ? Column(
                  children: [
                    _summaryValue('${data.targetKcal}', '每日目标热量', 'kcal'),
                    const Divider(height: 24, color: Colors.white24),
                    _summaryValue(
                      data.expectedWeeklyChangeKg.toStringAsFixed(2),
                      '预计每周减重',
                      'kg',
                    ),
                    const Divider(height: 24, color: Colors.white24),
                    _summaryValue('4', '执行阶段', '周'),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _summaryValue(
                        '${data.targetKcal}',
                        '每日目标热量',
                        'kcal',
                      ),
                    ),
                    Expanded(
                      child: _summaryValue(
                        data.expectedWeeklyChangeKg.toStringAsFixed(2),
                        '预计每周减重',
                        'kg',
                      ),
                    ),
                    Expanded(child: _summaryValue('4', '执行阶段', '周')),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        if (useStackedLayout)
          Column(
            children: [
              _target('蛋白质', '${data.proteinG} g', Icons.egg_alt_outlined),
              _target('饮水', '${data.waterMl} ml', Icons.water_drop_outlined),
              _target(
                '运动',
                '${data.exerciseDays} 天 / ${data.exerciseMinutes} 分钟',
                Icons.directions_run,
              ),
              _target(
                '睡眠',
                '${data.sleepHours.toStringAsFixed(1)} 小时',
                Icons.bedtime_outlined,
              ),
            ],
          )
        else
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _target('蛋白质', '${data.proteinG} g', Icons.egg_alt_outlined),
              _target('饮水', '${data.waterMl} ml', Icons.water_drop_outlined),
              _target(
                '运动',
                '${data.exerciseDays} 天 / ${data.exerciseMinutes} 分钟',
                Icons.directions_run,
              ),
              _target(
                '睡眠',
                '${data.sleepHours.toStringAsFixed(1)} 小时',
                Icons.bedtime_outlined,
              ),
            ],
          ),
        const SizedBox(height: 14),
        _card(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(),
            collapsedShape: const RoundedRectangleBorder(),
            title: const Text(
              '为什么这样安排',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _detail('BMI（估算）', data.bmi.toStringAsFixed(1)),
              _detail('基础代谢（估算）', '${data.bmrKcal} kcal'),
              _detail('每日消耗（估算）', '${data.tdeeKcal} kcal'),
              _detail('每日热量缺口', '${data.tdeeKcal - data.targetKcal} kcal'),
              _detail('公式版本', _ruleVersionLabel(data.ruleVersion)),
              const SizedBox(height: 8),
              const Text('以上结果为估算，不是医学诊断、治疗或处方。目标日期过早时，以安全建议日期为准。'),
              if (data.suggestedTargetDate != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('建议目标日期：${data.suggestedTargetDate}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('营养分配', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text('蛋白质 25% · ${data.proteinG} g'),
              Text('碳水 50% · ${data.carbsG} g'),
              Text('脂肪 25% · ${data.fatG} g'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: loading ? null : () => _primary(data, controller),
          child: Text(
            data.kind == PlanKind.preview
                ? state.recalculationPreview
                      ? '确认使用新计划'
                      : '确认采用计划'
                : data.kind == PlanKind.paused
                ? '恢复计划'
                : data.needsRecalculation
                ? '重新计算'
                : '查看今日目标',
          ),
        ),
        const SizedBox(height: 8),
        if (data.kind == PlanKind.preview)
          OutlinedButton(
            onPressed: loading
                ? null
                : state.recalculationPreview
                ? () => _cancelRecalculation(controller)
                : () => _reload(controller),
            child: const Text('暂不采用'),
          ),
        if (data.kind != PlanKind.paused) ...[
          if (!state.recalculationPreview)
            OutlinedButton(
              onPressed: loading ? null : () => _adjust(data, controller),
              child: const Text('调整目标'),
            ),
          if (data.kind == PlanKind.active)
            TextButton(
              onPressed: loading ? null : () => _pause(controller),
              child: const Text('暂停计划'),
            ),
        ],
        if (data.kind == PlanKind.active)
          TextButton(
            onPressed: () => _history(controller),
            child: const Text('查看历史版本'),
          ),
      ],
    );
  }

  Future<void> _reload(PlanController controller) async {
    _previewAdjustments = null;
    await controller.load();
  }

  Future<void> _generate(PlanController controller) async {
    _previewAdjustments = null;
    await controller.generate();
  }

  void _cancelRecalculation(PlanController controller) {
    _previewAdjustments = null;
    controller.cancelRecalculation();
  }

  Future<void> _primary(PlanData data, PlanController controller) async {
    if (controller.state.recalculationPreview) {
      await _feedback(controller.confirmRecalculation(), '新计划已生效');
      if (!controller.state.recalculationPreview) _previewAdjustments = null;
    } else if (data.kind == PlanKind.preview) {
      final ok = await controller.confirm(_previewAdjustments);
      if (ok) _previewAdjustments = null;
      if (ok && mounted) widget.onConfirmed();
    } else if (data.kind == PlanKind.paused) {
      await _feedback(controller.resume(), '计划已恢复');
    } else if (data.needsRecalculation) {
      _previewAdjustments = null;
      await controller.prepareRecalculation();
    } else {
      widget.onConfirmed();
    }
  }

  Widget _changes(PlanData oldPlan, PlanData newPlan) {
    final changes = <String>[
      if (oldPlan.targetKcal != newPlan.targetKcal)
        '每日热量：${oldPlan.targetKcal} → ${newPlan.targetKcal} kcal',
      if (oldPlan.waterMl != newPlan.waterMl)
        '每日饮水：${oldPlan.waterMl} → ${newPlan.waterMl} ml',
      if (oldPlan.exerciseDays != newPlan.exerciseDays ||
          oldPlan.exerciseMinutes != newPlan.exerciseMinutes)
        '每周运动：${oldPlan.exerciseDays} 天 / ${oldPlan.exerciseMinutes} 分钟 → ${newPlan.exerciseDays} 天 / ${newPlan.exerciseMinutes} 分钟',
      if (oldPlan.sleepHours != newPlan.sleepHours)
        '每日睡眠：${oldPlan.sleepHours.toStringAsFixed(1)} → ${newPlan.sleepHours.toStringAsFixed(1)} 小时',
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('变化摘要', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (changes.isEmpty)
            const Text('主要执行目标没有变化，确认后仍会保存新的计划版本。')
          else
            ...changes.map(
              (change) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(change),
              ),
            ),
          const SizedBox(height: 4),
          const Text('取消或返回不会修改当前计划。'),
        ],
      ),
    );
  }

  Future<void> _pause(PlanController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('暂停计划？'),
        content: const Text('暂停后，今日页将不再显示执行目标。恢复后继续当前阶段。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认暂停'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _feedback(controller.pause(), '计划已暂停');
  }

  Future<void> _adjust(PlanData data, PlanController controller) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AdjustDialog(data: data),
    );
    if (result == null) return;
    if (data.kind == PlanKind.preview) {
      _previewAdjustments = result;
      controller.applyPreviewAdjustments(result);
      _show('已应用到预览，确认后生效');
    } else {
      await _feedback(
        controller.adjust({...result, 'expectedVersion': data.version}),
        '目标已更新',
      );
    }
  }

  Future<void> _history(PlanController controller) async {
    final sessionRevision = widget.sessionRevision;
    try {
      final items = await controller.history();
      if (!mounted || widget.sessionRevision != sessionRevision) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        ),
        builder: (context) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: .8,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('历史版本', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Text('暂无历史版本')
                else
                  ...items.map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '版本 ${item['version'] ?? item['versionNumber'] ?? '-'}',
                      ),
                      subtitle: Text(_historyDate(item['createdAt'])),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted && widget.sessionRevision == sessionRevision) {
        _show(ApiClient.errorMessage(error));
      }
    }
  }

  Future<void> _feedback(Future<bool> operation, String success) async {
    final ok = await operation;
    if (mounted) {
      final controller = ref.read(planControllerProvider(widget.api));
      _show(ok ? success : controller.state.error ?? '操作失败，请重试');
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) => Card(
    child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
  );

  Widget _statusChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.mint,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.green,
        fontWeight: FontWeight.w700,
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

  Widget _summaryValue(String value, String label, String unit) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(unit, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      const SizedBox(height: 4),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    ],
  );

  Widget _target(String label, String value, IconData icon) => _card(
    child: Row(
      children: [
        Icon(icon, color: AppColors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );

  String _date(String value) =>
      value.length >= 10 ? value.substring(0, 10) : value;

  String _historyDate(Object? value) {
    if (value == null) return '保存的计划版本';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}年${local.month}月${local.day}日 $hour:$minute';
  }
}

String _ruleVersionLabel(String value) => switch (value) {
  'FAT_LOSS_V1' => '减脂公式 V1',
  _ => '当前公式',
};

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.data});
  final PlanData data;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  late double kcal = widget.data.targetKcal
      .clamp(widget.data.minimumTargetKcal, widget.data.maximumTargetKcal)
      .toDouble();
  late double water = widget.data.waterMl.clamp(1500, 3500).toDouble();
  late double days = widget.data.exerciseDays.clamp(0, 7).toDouble();
  late double minutes = widget.data.exerciseMinutes.clamp(0, 420).toDouble();
  late double sleep = widget.data.sleepHours.clamp(7, 9);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('调整目标'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _slider(
            '每日热量',
            kcal,
            widget.data.minimumTargetKcal.toDouble(),
            widget.data.maximumTargetKcal.toDouble(),
            50,
            'kcal',
            (v) => kcal = v,
          ),
          _slider('饮水', water, 1500, 3500, 100, 'ml', (v) => water = v),
          _slider('每周运动', days, 0, 7, 1, '天', (v) => days = v),
          _slider('周运动时长', minutes, 0, 420, 30, '分钟', (v) => minutes = v),
          _slider('睡眠', sleep, 7, 9, .5, '小时', (v) => sleep = v),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'targetKcal': kcal.round(),
          'waterMl': water.round(),
          'exerciseDays': days.round(),
          'exerciseMinutes': minutes.round(),
          'sleepHours': sleep,
        }),
        child: const Text('保存调整'),
      ),
    ],
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    double step,
    String unit,
    ValueChanged<double> update,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '$label：${step < 1 ? value.toStringAsFixed(1) : value.round()} $unit',
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: max == min ? null : ((max - min) / step).round(),
        onChanged: max == min ? null : (next) => setState(() => update(next)),
      ),
    ],
  );
}
