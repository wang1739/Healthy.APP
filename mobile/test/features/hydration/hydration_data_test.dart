import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';

void main() {
  test('解析设置、目标来源、记录和扩展字段', () {
    final day = HydrationDay.fromJson({
      'date': '2026-09-08',
      'status': 'READY',
      'consumedMl': 650,
      'targetMl': 2000,
      'remainingMl': 1350,
      'progress': .325,
      'targetSource': 'PLAN',
      'unknown': true,
      'settings': {'defaultCupMl': 250, 'version': 2, 'reminderEnabled': false},
      'entries': [
        {
          'id': 'e1',
          'amountMl': 250,
          'occurredAt': '2026-09-08T09:00:00+08:00',
          'source': 'QUICK',
        },
      ],
    });
    expect(day.targetSource, HydrationTargetSource.plan);
    expect(day.settings.defaultCupMl, 250);
    expect(day.entries.single.amountMl, 250);
    expect(day.progress, .325);
  });
}
