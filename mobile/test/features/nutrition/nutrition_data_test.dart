import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';

void main() {
  test('解析食物、份量和每百克营养', () {
    final food = Food.fromJson({
      'id': 'rice',
      'name': '米饭',
      'category': '主食',
      'caloriesPer100g': 116,
      'proteinPer100g': 2.6,
      'carbsPer100g': 25.9,
      'fatPer100g': 0.3,
      'custom': false,
      'portions': [
        {'id': 'bowl', 'label': '1 碗', 'grams': 150},
      ],
      'futureField': true,
    });

    expect(food.name, '米饭');
    expect(food.portions.single.grams, 150);
    expect(food.nutritionFor(150).calories, 174);
    expect(food.nutritionFor(150).carbs, closeTo(38.85, 0.001));
  });

  test('解析四餐、汇总和可空计划目标', () {
    final day = NutritionDay.fromJson(nutritionDayJson());

    expect(day.date, DateTime(2026, 9, 8));
    expect(day.status, NutritionDayStatus.ready);
    expect(day.meal(MealType.breakfast).entries.single.foodName, '鸡蛋');
    expect(day.summary.calories, 72);
    expect(day.target, isNull);
  });

  test('未知页面状态安全降级为错误', () {
    final json = nutritionDayJson()..['status'] = 'FUTURE_STATUS';
    expect(NutritionDay.fromJson(json).status, NutritionDayStatus.error);
  });
}

Map<String, dynamic> nutritionDayJson({String date = '2026-09-08'}) => {
  'date': date,
  'status': 'READY',
  'total': {'calories': 72, 'protein': 6.3, 'carbs': 0.4, 'fat': 4.8},
  'target': null,
  'meals': [
    {
      'mealType': 'BREAKFAST',
      'subtotal': {'calories': 72, 'protein': 6.3, 'carbs': 0.4, 'fat': 4.8},
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
};
