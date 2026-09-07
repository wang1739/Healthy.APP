import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class PlanPage extends StatelessWidget {
  const PlanPage({required this.onProtectedAction, super.key});

  final ValueChanged<String> onProtectedAction;

  @override
  Widget build(BuildContext context) => FeaturePlaceholder(
    title: '健康计划',
    description: '根据健康档案生成安全、可解释的生活计划。',
    icon: Icons.route_outlined,
    example: true,
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => onProtectedAction('生成健康计划'),
        child: const Text('生成我的计划'),
      ),
    ),
  );
}
