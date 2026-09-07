import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class NutritionPage extends StatelessWidget {
  const NutritionPage({required this.onProtectedAction, super.key});

  final ValueChanged<String> onProtectedAction;

  @override
  Widget build(BuildContext context) => FeaturePlaceholder(
    title: '饮食记录',
    description: '记录每一餐，了解热量与营养进度。',
    icon: Icons.restaurant_outlined,
    example: true,
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => onProtectedAction('记录饮食'),
        child: const Text('开始记录'),
      ),
    ),
  );
}
