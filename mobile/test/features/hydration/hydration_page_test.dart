import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:healthy/features/hydration/presentation/hydration_page.dart';

class Fake extends ApiClient {
  @override
  Future<HydrationDay> getHydrationDay(
    DateTime d, {
    required String timezone,
  }) async => HydrationDay.fromJson({
    'date': '2026-09-08',
    'status': 'EMPTY',
    'consumedMl': 0,
    'targetMl': 2000,
    'remainingMl': 2000,
    'progress': 0,
    'targetSource': 'DEFAULT',
    'settings': {
      'defaultCupMl': 250,
      'effectiveTargetMl': 2000,
      'reminderEnabled': false,
      'version': 0,
    },
    'entries': [],
  });
}

void main() {
  testWidgets('显示中文进度、预设和游客引导', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HydrationPage(
              api: Fake(),
              access: UserAccess.guest,
              sessionKey: 'g',
              onProtectedAction: (_) {},
              now: () => DateTime(2026, 9, 8),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final text in [
      '饮水记录',
      '已喝 0 ml',
      '目标 2000 ml',
      '剩余 2000 ml',
      '+250 ml',
      '100 ml',
      '500 ml',
      '登录后记录饮水',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('720×1600 与 1.3 倍字体可浏览主要操作', (t) async {
    t.view.physicalSize = const Size(720, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: HydrationPage(
              api: Fake(),
              access: UserAccess.guest,
              sessionKey: 'g',
              onProtectedAction: (_) {},
              now: () => DateTime(2026, 9, 8),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('+250 ml'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('自定义容量在弹窗关闭后提交且页面不崩溃', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HydrationPage(
              api: Fake(),
              access: UserAccess.profileComplete,
              sessionKey: 'user',
              onProtectedAction: (_) {},
              now: () => DateTime(2026, 9, 8, 9),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.text('自定义'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '450');
    await t.tap(find.text('添加'));
    await t.pumpAndSettle();

    expect(find.text('自定义容量'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
