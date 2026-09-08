import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class NutritionViewState {
  const NutritionViewState({
    required this.date,
    this.data,
    this.loading = false,
    this.stale = false,
    this.futureDate = false,
    this.error,
    this.draft,
    this.saving = false,
    this.saveError,
  });

  final DateTime date;
  final NutritionDay? data;
  final bool loading;
  final bool stale;
  final bool futureDate;
  final String? error;
  final Map<String, dynamic>? draft;
  final bool saving;
  final String? saveError;
}

class NutritionController extends ChangeNotifier {
  NutritionController(
    this.api, {
    required this.userKey,
    required this.now,
    DateTime? initialDate,
  }) : state = NutritionViewState(
         date: _dateOnly(initialDate ?? now()),
         futureDate: _dateOnly(initialDate ?? now()).isAfter(_dateOnly(now())),
       );

  final ApiClient api;
  final String userKey;
  final DateTime Function() now;
  final _cache = <String, NutritionDay>{};
  NutritionViewState state;
  int _request = 0;
  Future<void>? _saving;
  String? _idempotencyKey;
  bool _disposed = false;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> load(DateTime value, {bool force = false}) async {
    final date = _dateOnly(value);
    final key = formatLocalDate(date);
    final request = ++_request;
    final cached = _cache[key];
    state = NutritionViewState(
      date: date,
      data: cached,
      loading: force || cached == null,
      futureDate: date.isAfter(_dateOnly(now())),
    );
    notifyListeners();
    if (cached != null && !force) return;
    try {
      final data = await api.getNutritionDay(date);
      _cache[key] = data;
      if (_disposed || request != _request) return;
      state = NutritionViewState(
        date: date,
        data: data,
        futureDate: state.futureDate,
        draft: state.draft,
      );
    } catch (error) {
      if (_disposed || request != _request) return;
      state = NutritionViewState(
        date: date,
        data: cached,
        stale: cached != null,
        futureDate: state.futureDate,
        error: cached == null
            ? ApiClient.errorMessage(error)
            : '刷新失败，当前内容可能不是最新',
        draft: state.draft,
      );
    }
    notifyListeners();
  }

  Future<void> refresh() => load(state.date, force: true);

  void saveDraft(Map<String, dynamic> draft) {
    state = _copy(
      draft: Map<String, dynamic>.from(draft),
      clearSaveError: true,
    );
    _idempotencyKey ??= _newKey();
    notifyListeners();
  }

  Future<void> addDraft() => add(state.draft ?? const {});

  Future<void> add(Map<String, dynamic> draft) {
    if (state.futureDate || draft.isEmpty) return Future.value();
    final active = _saving;
    if (active != null) return active;
    saveDraft(draft);
    final operation = _write(() {
      final body = Map<String, dynamic>.from(draft)
        ..putIfAbsent('date', () => formatLocalDate(state.date));
      return api.addNutritionEntry(body, idempotencyKey: _idempotencyKey!);
    }, clearDraft: true);
    _saving = operation;
    return operation.whenComplete(() => _saving = null);
  }

  Future<void> update(String id, Map<String, dynamic> draft) {
    if (state.futureDate) return Future.value();
    final body = Map<String, dynamic>.from(draft)
      ..putIfAbsent('date', () => formatLocalDate(state.date));
    return _write(() => api.updateNutritionEntry(id, body), clearDraft: true);
  }

  Future<void> delete(String id) => state.futureDate
      ? Future.value()
      : _write(() => api.deleteNutritionEntry(id), clearDraft: true);

  Future<void> _write(
    Future<NutritionDay> Function() action, {
    required bool clearDraft,
  }) async {
    final existing = state.data;
    state = _copy(saving: true, clearSaveError: true);
    notifyListeners();
    try {
      final data = await action();
      _cache[formatLocalDate(data.date)] = data;
      if (_disposed) return;
      state = NutritionViewState(
        date: state.date,
        data: data,
        futureDate: state.futureDate,
        draft: clearDraft ? null : state.draft,
      );
      _idempotencyKey = null;
    } catch (error) {
      if (_disposed) return;
      state = NutritionViewState(
        date: state.date,
        data: existing,
        futureDate: state.futureDate,
        draft: state.draft,
        saveError: ApiClient.errorMessage(error),
      );
    }
    notifyListeners();
  }

  NutritionViewState _copy({
    Map<String, dynamic>? draft,
    bool? saving,
    bool clearSaveError = false,
  }) => NutritionViewState(
    date: state.date,
    data: state.data,
    loading: state.loading,
    stale: state.stale,
    futureDate: state.futureDate,
    error: state.error,
    draft: draft ?? state.draft,
    saving: saving ?? state.saving,
    saveError: clearSaveError ? null : state.saveError,
  );

  String _newKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  @override
  void dispose() {
    _disposed = true;
    _cache.clear();
    super.dispose();
  }
}

class NutritionProviderKey {
  const NutritionProviderKey(
    this.api,
    this.userKey,
    this.initialDate, {
    this.today,
  });

  final ApiClient api;
  final String userKey;
  final DateTime initialDate;
  final DateTime? today;

  @override
  bool operator ==(Object other) =>
      other is NutritionProviderKey &&
      identical(api, other.api) &&
      userKey == other.userKey &&
      formatLocalDate(initialDate) == formatLocalDate(other.initialDate) &&
      (today == null ? null : formatLocalDate(today!)) ==
          (other.today == null ? null : formatLocalDate(other.today!));

  @override
  int get hashCode => Object.hash(
    api,
    userKey,
    formatLocalDate(initialDate),
    today == null ? null : formatLocalDate(today!),
  );
}

final nutritionControllerProvider = ChangeNotifierProvider.autoDispose
    .family<NutritionController, NutritionProviderKey>(
      (ref, key) => NutritionController(
        key.api,
        userKey: key.userKey,
        initialDate: key.initialDate,
        now: () => key.today ?? DateTime.now(),
      ),
    );
