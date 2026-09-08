Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<dynamic> _list(Object? value) => value is List ? value : const [];

double _number(Object? value) => (value as num?)?.toDouble() ?? 0;

enum NutritionDayStatus { ready, empty, noPlan, riskBlocked, error }

NutritionDayStatus _dayStatus(Object? value) => switch (value) {
  'READY' => NutritionDayStatus.ready,
  'EMPTY' => NutritionDayStatus.empty,
  'NO_PLAN' => NutritionDayStatus.noPlan,
  'RISK_BLOCKED' => NutritionDayStatus.riskBlocked,
  _ => NutritionDayStatus.error,
};

enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeDetails on MealType {
  String get wireName => switch (this) {
    MealType.breakfast => 'BREAKFAST',
    MealType.lunch => 'LUNCH',
    MealType.dinner => 'DINNER',
    MealType.snack => 'SNACK',
  };

  String get label => switch (this) {
    MealType.breakfast => '早餐',
    MealType.lunch => '午餐',
    MealType.dinner => '晚餐',
    MealType.snack => '加餐',
  };

  static MealType parse(Object? value) => switch (value) {
    'LUNCH' => MealType.lunch,
    'DINNER' => MealType.dinner,
    'SNACK' => MealType.snack,
    _ => MealType.breakfast,
  };
}

class NutritionValues {
  const NutritionValues({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory NutritionValues.fromJson(Map<String, dynamic> json) =>
      NutritionValues(
        calories: _number(json['calories'] ?? json['targetKcal']),
        protein: _number(json['protein'] ?? json['proteinG']),
        carbs: _number(json['carbs'] ?? json['carbsG']),
        fat: _number(json['fat'] ?? json['fatG']),
      );

  static const zero = NutritionValues(
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
  );

  final double calories;
  final double protein;
  final double carbs;
  final double fat;
}

class FoodPortion {
  const FoodPortion({
    required this.id,
    required this.label,
    required this.grams,
  });

  factory FoodPortion.fromJson(Map<String, dynamic> json) => FoodPortion(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    grams: _number(json['grams']),
  );

  final String id;
  final String label;
  final double grams;
}

class Food {
  const Food({
    required this.id,
    required this.name,
    required this.category,
    required this.per100g,
    required this.portions,
    required this.custom,
  });

  factory Food.fromJson(Map<String, dynamic> json) => Food(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    per100g: NutritionValues(
      calories: _number(json['caloriesPer100g']),
      protein: _number(json['proteinPer100g']),
      carbs: _number(json['carbsPer100g']),
      fat: _number(json['fatPer100g']),
    ),
    portions: _list(json['portions'])
        .map((item) => FoodPortion.fromJson(_map(item)))
        .toList(growable: false),
    custom: json['custom'] == true,
  );

  final String id;
  final String name;
  final String category;
  final NutritionValues per100g;
  final List<FoodPortion> portions;
  final bool custom;

  NutritionValues nutritionFor(double grams) => NutritionValues(
    calories: per100g.calories * grams / 100,
    protein: per100g.protein * grams / 100,
    carbs: per100g.carbs * grams / 100,
    fat: per100g.fat * grams / 100,
  );
}

class FoodSuggestions {
  const FoodSuggestions({required this.recent, required this.frequent});

  factory FoodSuggestions.fromJson(Map<String, dynamic> json) =>
      FoodSuggestions(
        recent: _list(json['recent'])
            .map((item) => Food.fromJson(_map(item)))
            .toList(growable: false),
        frequent: _list(json['frequent'] ?? json['common'])
            .map((item) => Food.fromJson(_map(item)))
            .toList(growable: false),
      );

  final List<Food> recent;
  final List<Food> frequent;
}

class MealEntry {
  const MealEntry({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.grams,
    required this.nutrition,
  });

  factory MealEntry.fromJson(Map<String, dynamic> json) => MealEntry(
    id: json['id']?.toString() ?? '',
    foodId: json['foodId']?.toString(),
    foodName: (json['foodName'] ?? json['foodNameSnapshot'])?.toString() ?? '',
    grams: _number(json['grams']),
    nutrition: NutritionValues.fromJson(json),
  );

  final String id;
  final String? foodId;
  final String foodName;
  final double grams;
  final NutritionValues nutrition;
}

class MealGroup {
  const MealGroup({
    required this.type,
    required this.subtotal,
    required this.entries,
  });

  factory MealGroup.fromJson(Map<String, dynamic> json) => MealGroup(
    type: MealTypeDetails.parse(json['type'] ?? json['mealType']),
    subtotal: NutritionValues.fromJson(_map(json['subtotal'])),
    entries: _list(json['entries'])
        .map((item) => MealEntry.fromJson(_map(item)))
        .toList(growable: false),
  );

  factory MealGroup.empty(MealType type) =>
      MealGroup(type: type, subtotal: NutritionValues.zero, entries: const []);

  final MealType type;
  final NutritionValues subtotal;
  final List<MealEntry> entries;
}

class NutritionDay {
  const NutritionDay({
    required this.date,
    required this.status,
    required this.meals,
    required this.summary,
    required this.target,
    this.message,
  });

  factory NutritionDay.fromJson(Map<String, dynamic> json) {
    final parsed = <MealType, MealGroup>{};
    for (final item in _list(json['meals'])) {
      final meal = MealGroup.fromJson(_map(item));
      parsed[meal.type] = meal;
    }
    return NutritionDay(
      date: DateTime.parse(json['date'] as String),
      status: _dayStatus(json['status']),
      meals: [
        for (final type in MealType.values)
          parsed[type] ?? MealGroup.empty(type),
      ],
      summary: NutritionValues.fromJson(_map(json['total'] ?? json['summary'])),
      target: json['target'] == null
          ? null
          : NutritionValues.fromJson(_map(json['target'])),
      message: json['message']?.toString(),
    );
  }

  final DateTime date;
  final NutritionDayStatus status;
  final List<MealGroup> meals;
  final NutritionValues summary;
  final NutritionValues? target;
  final String? message;

  MealGroup meal(MealType type) =>
      meals.firstWhere((meal) => meal.type == type);
}
