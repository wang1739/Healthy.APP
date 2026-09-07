import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    title: '健康报告',
    description: '查看饮食、运动、睡眠与体重的长期变化。',
    icon: Icons.insights_outlined,
  );
}
