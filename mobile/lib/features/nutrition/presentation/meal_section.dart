import 'package:flutter/material.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';

class MealSection extends StatelessWidget {
  const MealSection({
    required this.meal,
    required this.readOnly,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final MealGroup meal;
  final bool readOnly;
  final VoidCallback onAdd;
  final ValueChanged<MealEntry> onEdit;
  final ValueChanged<MealEntry> onDelete;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      initiallyExpanded: meal.type == MealType.breakfast,
      title: Text(meal.type.label),
      subtitle: Text('${meal.subtotal.calories.round()} kcal'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (meal.entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('还没有记录'),
          ),
        for (final entry in meal.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.foodName),
            subtitle: Text(
              '${entry.grams.toStringAsFixed(entry.grams % 1 == 0 ? 0 : 1)} g · ${entry.nutrition.calories.round()} kcal',
            ),
            onTap: readOnly ? null : () => onEdit(entry),
            trailing: readOnly
                ? null
                : IconButton(
                    tooltip: '删除${entry.foodName}',
                    onPressed: () => onDelete(entry),
                    icon: const Icon(Icons.delete_outline),
                  ),
          ),
        if (!readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text('添加${meal.type.label}'),
            ),
          ),
      ],
    ),
  );
}
