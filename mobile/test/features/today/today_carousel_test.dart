import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/today/presentation/today_carousel.dart';

void main() {
  test('三张高清照片均已打包为本地资源', () async {
    for (var index = 1; index <= 3; index++) {
      final bytes = await rootBundle.load(
        'assets/today/healthy-meal-$index.png',
      );
      expect(bytes.lengthInBytes, greaterThan(100000));
    }
  });

  testWidgets('轮播包含中文文案、页码指示和读屏语义', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: TodayCarousel(),
          ),
        ),
      ),
    );

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('把均衡饮食放进每一天'), findsOneWidget);
    expect(find.byKey(const Key('today-carousel-indicator-0')), findsOneWidget);
    expect(find.byKey(const Key('today-carousel-indicator-1')), findsOneWidget);
    expect(find.byKey(const Key('today-carousel-indicator-2')), findsOneWidget);
    expect(find.bySemanticsLabel('健康餐食轮播，第 1 张，共 3 张'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('认真吃饭，也能轻盈生活'), findsOneWidget);
  });

  testWidgets('减少动画时停止自动播放并在卸载时释放计时器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: TodayCarousel(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(find.bySemanticsLabel('健康餐食轮播，第 1 张，共 3 张'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
}
