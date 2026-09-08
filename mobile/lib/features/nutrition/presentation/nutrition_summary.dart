import 'package:flutter/material.dart';
import 'package:healthy/core/theme/app_colors.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';

class NutritionSummary extends StatelessWidget {
  const NutritionSummary({
    required this.summary,
    required this.target,
    required this.onOpenPlan,
    super.key,
  });

  final NutritionValues summary;
  final NutritionValues? target;
  final VoidCallback onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final goal = target;
    final progress = goal == null || goal.calories <= 0
        ? null
        : (summary.calories / goal.calories).clamp(0.0, 1.0);
    return Card(
      key: const Key('nutrition-summary-card'),
      color: AppColors.green,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('今日摄入', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              '${summary.calories.round()} kcal',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (goal != null) ...[
              Text(
                '目标 ${goal.calories.round()} kcal',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
              if (summary.calories > goal.calories) ...[
                const SizedBox(height: 6),
                const Text(
                  '今天已超过目标，下一餐清淡一些就好',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              const Text('尚未生成减脂计划', style: TextStyle(color: Colors.white)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onOpenPlan,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('生成减脂计划'),
                ),
              ),
            ],
            const Divider(color: Colors.white24),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _value('蛋白质', summary.protein),
                _value('碳水', summary.carbs),
                _value('脂肪', summary.fat),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _value(String label, double value) => Text(
    '$label ${value.toStringAsFixed(1)} g',
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
  );
}
