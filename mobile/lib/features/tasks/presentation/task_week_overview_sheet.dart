import 'package:flutter/material.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';

class TaskWeekOverviewSheet extends StatelessWidget {
  const TaskWeekOverviewSheet({required this.week, super.key});
  final TaskWeek? week;
  @override
  Widget build(BuildContext context) {
    final value = week;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: value == null
            ? const Text('最近 7 天数据暂时无法加载')
            : ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    '最近 7 天概览',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text('应完成 ${value.expectedCount}'),
                      Text('已完成 ${value.completedCount}'),
                      Text('已跳过 ${value.skippedCount}'),
                      Text('已延期 ${value.postponedCount}'),
                      Text('当前逾期 ${value.overdueCount}'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    value.completionRate == null
                        ? '暂无可计算的完成率'
                        : '完成率 ${(value.completionRate! * 100).round()}%',
                  ),
                  if (value.completionRate != null)
                    LinearProgressIndicator(
                      value: value.completionRate!.clamp(0, 1),
                    ),
                  const SizedBox(height: 18),
                  for (final item in value.categories) ...[
                    Text(
                      '${item.category.label} ${item.completedCount} / ${item.expectedCount}',
                    ),
                    LinearProgressIndicator(
                      value: item.expectedCount == 0
                          ? 0
                          : item.completedCount / item.expectedCount,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
    );
  }
}
