import 'package:flutter/material.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';

class HydrationProgress extends StatelessWidget {
  const HydrationProgress({required this.day, super.key});
  final HydrationDay day;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xffe7f5ef),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '已喝 ${day.consumedMl} ml',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: day.progress.clamp(0, 1),
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text('目标 ${day.targetMl} ml'),
            Text(
              day.consumedMl > day.targetMl
                  ? '已超出 ${day.consumedMl - day.targetMl} ml'
                  : '剩余 ${day.remainingMl} ml',
            ),
          ],
        ),
      ],
    ),
  );
}
