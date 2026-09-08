import 'package:flutter/material.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';

class FoodSearchView extends StatefulWidget {
  const FoodSearchView({
    required this.api,
    required this.onSelected,
    required this.onCustom,
    super.key,
  });

  final ApiClient api;
  final ValueChanged<Food> onSelected;
  final VoidCallback onCustom;

  @override
  State<FoodSearchView> createState() => _FoodSearchViewState();
}

class _FoodSearchViewState extends State<FoodSearchView> {
  FoodSuggestions? _suggestions;
  List<Food>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final value = await widget.api.getFoodSuggestions();
      if (mounted) setState(() => _suggestions = value);
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    try {
      final value = await widget.api.searchFoods(query: query.trim());
      if (mounted) setState(() => _results = value);
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        decoration: const InputDecoration(
          labelText: '搜索食物',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 12),
      if (_error != null) Text(_error!),
      if (_results != null) ...[
        if (_results!.isEmpty) const Text('没有找到相关食物'),
        ..._results!.map(_foodTile),
      ] else if (_suggestions == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        const Text('最近吃过', style: TextStyle(fontWeight: FontWeight.w700)),
        ..._suggestions!.recent.map(_foodTile),
        const SizedBox(height: 8),
        const Text('常用食物', style: TextStyle(fontWeight: FontWeight.w700)),
        ..._suggestions!.frequent.map(_foodTile),
      ],
      TextButton.icon(
        onPressed: widget.onCustom,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('自定义食物'),
      ),
    ],
  );

  Widget _foodTile(Food food) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(food.name),
    subtitle: Text('${food.per100g.calories.round()} kcal / 100 g'),
    onTap: () => widget.onSelected(food),
  );
}
