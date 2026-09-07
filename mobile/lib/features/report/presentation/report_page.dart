import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class ReportPage extends StatelessWidget {
  const ReportPage({required this.onProtectedAction, super.key});

  final ValueChanged<String> onProtectedAction;

  @override
  Widget build(BuildContext context) => FeaturePlaceholder(
    title: '健康报告',
    description: '查看饮食、运动、睡眠与体重的长期变化。',
    icon: Icons.insights_outlined,
    example: true,
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => onProtectedAction('生成健康报告'),
        child: const Text('生成我的报告'),
      ),
    ),
  );
}
