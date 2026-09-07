import 'package:flutter/material.dart';
import 'package:healthy/core/theme/app_spacing.dart';

class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    required this.title,
    required this.description,
    required this.icon,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.small),
          Text(description),
          const SizedBox(height: AppSpacing.large),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Row(
                children: [
                  Icon(icon, size: 30),
                  const SizedBox(width: AppSpacing.medium),
                  const Expanded(child: Text('基础框架已就绪，业务功能将在下一阶段接入。')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
