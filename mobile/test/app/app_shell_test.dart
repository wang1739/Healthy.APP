import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/app.dart';
import 'package:healthy/core/api/backend_status.dart';

void main() {
  testWidgets('shows five destinations and switches pages', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: const HealthyApp(),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['今日', '饮食', '计划', '报告', '我的']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('今日概览'), findsOneWidget);

    await tester.tap(find.text('饮食'));
    await tester.pumpAndSettle();

    expect(find.text('饮食记录'), findsOneWidget);
  });

  testWidgets('uses the compact six-pixel card radius', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStatusProvider.overrideWith(
            (ref) async => BackendStatus.connected,
          ),
        ],
        child: const HealthyApp(),
      ),
    );

    final context = tester.element(find.byType(Card).first);
    final shape = Theme.of(context).cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(6));
  });
}
