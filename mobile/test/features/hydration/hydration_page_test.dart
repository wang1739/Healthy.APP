import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:healthy/features/hydration/presentation/hydration_page.dart';

class Fake extends ApiClient {
  int consumed = 0;
  int calls = 0;

  @override
  Future<HydrationDay> getHydrationDay(
    DateTime d, {
    required String timezone,
  }) async {
    calls++;
    return HydrationDay.fromJson({
      'date': '2026-09-08',
      'status': 'EMPTY',
      'consumedMl': consumed,
      'targetMl': 2000,
      'remainingMl': 2000 - consumed,
      'progress': consumed / 2000,
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

  testWidgets('重新进入饮水页会刷新当天饮水量', (t) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async => 'Asia/Shanghai',
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_timezone'),
        null,
      ),
    );
    final api = Fake();
    var active = false;
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                Expanded(
                  child: HydrationPage(
                    api: api,
                    access: UserAccess.profileComplete,
                    sessionKey: 'user',
                    active: active,
                    onProtectedAction: (_) {},
                    now: () => DateTime(2026, 9, 8),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => active = true),
                  child: const Text('切回饮水'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('已喝 0 ml'), findsOneWidget);

    api.consumed = 500;
    await t.tap(find.text('切回饮水'));
    await t.pumpAndSettle();

    expect(api.calls, 2);
    expect(find.text('已喝 500 ml'), findsOneWidget);
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
