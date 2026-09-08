import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:healthy/features/hydration/presentation/hydration_settings_sheet.dart';

void main() {
  testWidgets('设置表单使用中文并保留权限拒绝可用', (t) async {
    final s = HydrationSettings.fromJson({
      'defaultCupMl': 250,
      'effectiveTargetMl': 2000,
      'reminderEnabled': false,
      'version': 0,
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HydrationSettingsSheet(
            settings: s,
            onSave: (_) async {},
            onAdoptPlan: () async {},
          ),
        ),
      ),
    );
    expect(find.text('饮水设置'), findsOneWidget);
    expect(find.text('每日目标（ml）'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
  });
}
