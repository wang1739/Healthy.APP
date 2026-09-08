import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/nutrition/presentation/food_search_view.dart';

class FoodEntrySheet extends StatefulWidget {
  const FoodEntrySheet({
    required this.api,
    required this.initialMeal,
    required this.onSave,
    this.initialEntry,
    super.key,
  });

  final ApiClient api;
  final MealType initialMeal;
  final MealEntry? initialEntry;
  final FutureOr<void> Function(Map<String, dynamic>) onSave;

  @override
  State<FoodEntrySheet> createState() => _FoodEntrySheetState();
}

class _FoodEntrySheetState extends State<FoodEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _grams = TextEditingController();
  final _baseGrams = TextEditingController(text: '100');
  final _name = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController(text: '0');
  final _carbs = TextEditingController(text: '0');
  final _fat = TextEditingController(text: '0');
  late MealType _meal;
  Food? _food;
  bool _custom = false;
  bool _saveToMyFoods = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _meal = widget.initialMeal;
    final entry = widget.initialEntry;
    if (entry != null) {
      _grams.text = _format(entry.grams);
      final ratio = entry.grams == 0 ? 0 : 100 / entry.grams;
      if (entry.foodId == null) {
        _custom = true;
        _name.text = entry.foodName;
        _calories.text = _format(entry.nutrition.calories * ratio);
        _protein.text = _format(entry.nutrition.protein * ratio);
        _carbs.text = _format(entry.nutrition.carbs * ratio);
        _fat.text = _format(entry.nutrition.fat * ratio);
      } else {
        _food = Food(
          id: entry.foodId!,
          name: entry.foodName,
          category: '',
          per100g: NutritionValues(
            calories: entry.nutrition.calories * ratio,
            protein: entry.nutrition.protein * ratio,
            carbs: entry.nutrition.carbs * ratio,
            fat: entry.nutrition.fat * ratio,
          ),
          portions: const [],
          custom: false,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _grams,
      _baseGrams,
      _name,
      _calories,
      _protein,
      _carbs,
      _fat,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.initialEntry == null ? '添加食物' : '编辑食物',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final type in MealType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _meal == type,
                    onSelected: (_) => setState(() => _meal = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_food == null && !_custom)
              FoodSearchView(
                api: widget.api,
                onSelected: (food) => setState(() {
                  _food = food;
                  if (food.portions.isNotEmpty) {
                    _grams.text = _format(food.portions.first.grams);
                  }
                }),
                onCustom: () => setState(() {
                  _custom = true;
                  _grams.text = '100';
                }),
              )
            else if (_custom)
              _customForm()
            else
              _foodForm(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_food != null || _custom) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _foodForm() {
    final food = _food!;
    final grams = double.tryParse(_grams.text) ?? 0;
    final preview = food.nutritionFor(grams);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                food.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _food = null),
              child: const Text('重选'),
            ),
          ],
        ),
        if (food.portions.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final portion in food.portions)
                ChoiceChip(
                  label: Text(portion.label),
                  selected: grams == portion.grams,
                  onSelected: (_) =>
                      setState(() => _grams.text = _format(portion.grams)),
                ),
            ],
          ),
        TextFormField(
          controller: _grams,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '精确克数', suffixText: 'g'),
          onChanged: (_) => setState(() {}),
          validator: _validateGrams,
        ),
        const SizedBox(height: 12),
        Text('${preview.calories.round()} kcal'),
        Text(
          '蛋白质 ${preview.protein.toStringAsFixed(1)} g · 碳水 ${preview.carbs.toStringAsFixed(1)} g · 脂肪 ${preview.fat.toStringAsFixed(1)} g',
        ),
      ],
    );
  }

  Widget _customForm() {
    final grams = double.tryParse(_grams.text) ?? 0;
    final base = double.tryParse(_baseGrams.text) ?? 0;
    final factor = base > 0 ? grams / base : 0;
    final previewCalories = (double.tryParse(_calories.text) ?? 0) * factor;
    final previewProtein = (double.tryParse(_protein.text) ?? 0) * factor;
    final previewCarbs = (double.tryParse(_carbs.text) ?? 0) * factor;
    final previewFat = (double.tryParse(_fat.text) ?? 0) * factor;
    return Column(
      children: [
        TextFormField(
          key: const Key('custom-name'),
          controller: _name,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '食物名称'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请输入食物名称' : null,
        ),
        TextFormField(
          controller: _grams,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '本次克数', suffixText: 'g'),
          onChanged: (_) => setState(() {}),
          validator: _validateGrams,
        ),
        TextFormField(
          controller: _baseGrams,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '营养基准克数',
            suffixText: 'g',
          ),
          onChanged: (_) => setState(() {}),
          validator: _validateGrams,
        ),
        TextFormField(
          key: const Key('custom-calories'),
          controller: _calories,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '基准份量热量',
            suffixText: 'kcal',
          ),
          onChanged: (_) => setState(() {}),
          validator: _validateNonNegative,
        ),
        for (final field in [
          (_protein, '基准份量蛋白质'),
          (_carbs, '基准份量碳水'),
          (_fat, '基准份量脂肪'),
        ])
          TextFormField(
            controller: field.$1,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: field.$2, suffixText: 'g'),
            onChanged: (_) => setState(() {}),
            validator: _validateNonNegative,
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${previewCalories.round()} kcal · 蛋白质 ${previewProtein.toStringAsFixed(1)} g · 碳水 ${previewCarbs.toStringAsFixed(1)} g · 脂肪 ${previewFat.toStringAsFixed(1)} g',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _saveToMyFoods,
          onChanged: (value) => setState(() => _saveToMyFoods = value ?? false),
          title: const Text('保存到我的食物'),
        ),
      ],
    );
  }

  String? _validateGrams(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || number <= 0 || number > 5000
        ? '请输入 0–5000 克之间的数值'
        : null;
  }

  String? _validateNonNegative(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || number < 0 ? '请输入非负数值' : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final payload = <String, dynamic>{
      'mealType': _meal.wireName,
      'grams': double.parse(_grams.text),
      if (_food?.id.isNotEmpty == true) 'foodId': _food!.id,
      if (_custom) ...{
        'foodName': _name.text.trim(),
        'baseGrams': double.parse(_baseGrams.text),
        'calories': double.parse(_calories.text),
        'protein': double.parse(_protein.text),
        'carbs': double.parse(_carbs.text),
        'fat': double.parse(_fat.text),
        'saveCustomFood': _saveToMyFoods,
      },
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(payload);
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _format(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
}
