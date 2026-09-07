import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    title: '健康计划',
    description: '根据健康档案生成安全、可解释的生活计划。',
    icon: Icons.route_outlined,
  );
}
