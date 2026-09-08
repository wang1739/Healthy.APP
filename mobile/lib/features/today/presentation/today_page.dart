import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/core/api/backend_status.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_colors.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/plan/application/plan_controller.dart';
import 'package:healthy/app/session_controller.dart';

class TodayPage extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backendStatusProvider);
    final connected = status.value == BackendStatus.connected;
    final plan = access == UserAccess.profileComplete
        ? ref.watch(planControllerProvider(api)).state.data
        : null;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          Text('今日概览', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.small),
          const Text('先把每天最重要的健康行动放在这里。'),
          const SizedBox(height: AppSpacing.large),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.mint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.eco_outlined,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.medium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '轻食记服务',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          status.isLoading
                              ? '正在连接'
                              : connected
                              ? '服务已连接'
                              : '服务暂未启动',
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    connected ? Icons.check_circle : Icons.cloud_off_outlined,
                    color: connected ? AppColors.green : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          if (plan != null && plan.kind == PlanKind.active) ...[
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onOpenPlan,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.medium),
                  child: Row(
                    children: [
                      const Icon(Icons.route_outlined, color: AppColors.green),
                      const SizedBox(width: AppSpacing.medium),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '当前减脂计划',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '每日 ${plan.targetKcal} kcal · 第 ${plan.currentWeek} 周',
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.large),
          ],
          FilledButton(
            onPressed: () => onProtectedAction('记录今日健康行动'),
            child: const Text('记录今日健康行动'),
          ),
        ],
      ),
    );
  }
}
