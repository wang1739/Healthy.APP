import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class NutritionPage extends StatelessWidget {
  const NutritionPage({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    title: '饮食记录',
    description: '记录每一餐，了解热量与营养进度。',
    icon: Icons.restaurant_outlined,
  );
}
