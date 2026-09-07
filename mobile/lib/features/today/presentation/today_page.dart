import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/core/api/backend_status.dart';
import 'package:healthy/core/theme/app_colors.dart';
import 'package:healthy/core/theme/app_spacing.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backendStatusProvider);
    final connected = status.value == BackendStatus.connected;

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
        ],
      ),
    );
  }
}
