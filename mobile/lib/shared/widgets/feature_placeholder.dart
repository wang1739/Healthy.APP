import 'package:flutter/material.dart';
import 'package:healthy/core/theme/app_spacing.dart';

class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    required this.title,
    required this.description,
    required this.icon,
    this.example = false,
    this.child,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool example;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (example) const Chip(label: Text('示例')),
            ],
          ),
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
          if (child != null) ...[
            const SizedBox(height: AppSpacing.large),
            child!,
          ],
        ],
      ),
    );
  }
}
