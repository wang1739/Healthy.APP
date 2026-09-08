import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/nutrition/presentation/nutrition_page.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.fail = false, this.target = true}) : super(dio: Dio());

  final bool fail;
  final bool target;
  int updates = 0;
  int deletes = 0;

  @override
  Future<NutritionDay> getNutritionDay(DateTime date) async {
    if (fail) throw DioException(requestOptions: RequestOptions());
    return NutritionDay.fromJson({
      'date':
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'status': 'READY',
      'total': {'calories': 520, 'protein': 32.5, 'carbs': 60, 'fat': 15.2},
      'target': target
          ? {'calories': 1500, 'protein': 110, 'carbs': 160, 'fat': 45}
          : null,
      'meals': [
        {
          'mealType': 'BREAKFAST',
          'subtotal': {
            'calories': 72,
            'protein': 6.3,
            'carbs': 0.4,
            'fat': 4.8,
          },
          'entries': [
            {
              'id': 'entry-1',
              'foodId': 'egg',
              'foodName': '鸡蛋',
              'grams': 50,
              'calories': 72,
              'protein': 6.3,
              'carbs': 0.4,
              'fat': 4.8,
            },
          ],
        },
      ],
    });
  }

  @override
  Future<FoodSuggestions> getFoodSuggestions({int limit = 8}) async =>
      const FoodSuggestions(recent: [], frequent: []);

  @override
  Future<NutritionDay> updateNutritionEntry(
    String id,
    Map<String, dynamic> data,
  ) async {
    updates++;
    return getNutritionDay(DateTime.parse(data['date'] as String));
  }

  @override
  Future<NutritionDay> deleteNutritionEntry(String id) async {
    deletes++;
    return getNutritionDay(DateTime(2026, 9, 8));
  }
}

Widget page({
  required UserAccess access,
  ApiClient? api,
  DateTime? initialDate,
  double textScale = 1,
  bool riskBlocked = false,
}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: const Size(320, 700),
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: NutritionPage(
      api: api ?? _FakeApi(),
      access: access,
      sessionKey: 'session-a',
      initialDate: initialDate ?? DateTime(2026, 9, 8),
      now: () => DateTime(2026, 9, 8),
      riskBlocked: riskBlocked,
      onProtectedAction: (_) {},
      onOpenPlan: () {},
    ),
  ),
);

void main() {
  testWidgets('游客看到示例且记录操作进入既有限制闭环', (tester) async {
    String? action;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: NutritionPage(
            api: _FakeApi(),
            access: UserAccess.guest,
            sessionKey: 'guest',
            now: () => DateTime(2026, 9, 8),
            onProtectedAction: (value) => action = value,
            onOpenPlan: () {},
          ),
        ),
      ),
    );

    expect(find.text('登录后记录每一餐'), findsOneWidget);
    await tester.tap(find.text('开始记录'));
    expect(action, '记录饮食');
  });

  testWidgets('已建档显示单卡总览和可折叠四餐', (tester) async {
    await tester.pumpWidget(page(access: UserAccess.profileComplete));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nutrition-summary-card')), findsOneWidget);
    expect(find.text('520 kcal'), findsOneWidget);
    for (final meal in ['早餐', '午餐', '晚餐']) {
      expect(find.text(meal), findsOneWidget);
    }
    expect(find.text('鸡蛋'), findsOneWidget);
    await tester.tap(find.text('早餐'));
    await tester.pumpAndSettle();
    expect(find.text('鸡蛋'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('加餐'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('加餐'), findsOneWidget);
  });

  testWidgets('无计划不伪造百分比并提供计划入口', (tester) async {
    await tester.pumpWidget(
      page(access: UserAccess.profileComplete, api: _FakeApi(target: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未生成减脂计划'), findsOneWidget);
    expect(find.text('生成减脂计划'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('未来日期只读，读取失败可重试', (tester) async {
    await tester.pumpWidget(
      page(
        access: UserAccess.profileComplete,
        initialDate: DateTime(2026, 9, 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('未来日期仅可查看'), findsOneWidget);
    expect(find.text('添加食物'), findsNothing);

    await tester.pumpWidget(
      page(access: UserAccess.profileComplete, api: _FakeApi(fail: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新加载'), findsOneWidget);
  });

  testWidgets('风险拦截不展示普通计划目标', (tester) async {
    await tester.pumpWidget(
      page(access: UserAccess.profileComplete, riskBlocked: true),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('不展示普通减脂目标'), findsOneWidget);
    expect(find.text('目标 1500 kcal'), findsNothing);
  });

  testWidgets('窄屏与 1.3 倍字体可滚动访问四餐', (tester) async {
    await tester.pumpWidget(
      page(access: UserAccess.profileComplete, textScale: 1.3),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('加餐'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('加餐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部添加操作使用 6px 圆角', (tester) async {
    await tester.pumpWidget(page(access: UserAccess.profileComplete));
    await tester.pumpAndSettle();

    final button = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    final shape = button.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('编辑复用录入弹层且删除需要中文确认', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(page(access: UserAccess.profileComplete, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('鸡蛋'));
    await tester.pumpAndSettle();
    expect(find.text('编辑食物'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(api.updates, 1);

    await tester.tap(find.byTooltip('删除鸡蛋'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条记录？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(api.deletes, 1);
  });
}
