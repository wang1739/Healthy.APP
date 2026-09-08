import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/nutrition/presentation/food_entry_sheet.dart';

Food food(String id, String name) => Food.fromJson({
  'id': id,
  'name': name,
  'category': '主食',
  'caloriesPer100g': 116,
  'proteinPer100g': 2.6,
  'carbsPer100g': 25.9,
  'fatPer100g': 0.3,
  'custom': false,
  'portions': [
    {'id': 'bowl', 'label': '1 碗', 'grams': 150},
  ],
});

class _FakeApi extends ApiClient {
  _FakeApi() : super(dio: Dio());

  String? query;

  @override
  Future<FoodSuggestions> getFoodSuggestions({int limit = 8}) async =>
      FoodSuggestions(
        recent: [food('rice', '米饭')],
        frequent: [food('egg', '鸡蛋')],
      );

  @override
  Future<List<Food>> searchFoods({
    String query = '',
    String scope = 'ALL',
    int limit = 20,
  }) async {
    this.query = query;
    return query == '燕麦' ? [food('oat', '燕麦')] : [];
  }
}

Widget _sheet(_FakeApi api, ValueChanged<Map<String, dynamic>> onSave) =>
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: FoodEntrySheet(
          api: api,
          initialMeal: MealType.breakfast,
          onSave: onSave,
        ),
      ),
    );

void main() {
  testWidgets('先显示最近与常用，并支持中文搜索', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_sheet(api, (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('最近吃过'), findsOneWidget);
    expect(find.text('常用食物'), findsOneWidget);
    expect(find.text('米饭'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '燕麦');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.query, '燕麦');
    expect(find.text('燕麦'), findsAtLeastNWidgets(2));
  });

  testWidgets('份量优先并随克数即时预览', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(_sheet(_FakeApi(), (value) => saved = value));
    await tester.pumpAndSettle();
    await tester.tap(find.text('米饭'));
    await tester.pump();

    expect(find.text('1 碗'), findsOneWidget);
    await tester.tap(find.text('1 碗'));
    await tester.pump();
    expect(find.text('174 kcal'), findsOneWidget);
    await tester.tap(find.text('保存'));
    expect(saved?['grams'], 150);
    expect(saved?['mealType'], 'BREAKFAST');
  });

  testWidgets('自定义食物校验并可保存到我的食物', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(_sheet(_FakeApi(), (value) => saved = value));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义食物'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('保存'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入食物名称'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('custom-name')), '自制沙拉');
    await tester.enterText(find.byKey(const Key('custom-calories')), '80');
    await tester.pump();
    expect(find.textContaining('80 kcal'), findsOneWidget);
    await tester.tap(find.text('保存到我的食物'));
    await tester.scrollUntilVisible(
      find.text('保存'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存'));
    expect(saved?['foodName'], '自制沙拉');
    expect(saved?['saveCustomFood'], isTrue);
    expect(saved?['baseGrams'], 100);
    expect(saved?['calories'], 80);
  });
}
