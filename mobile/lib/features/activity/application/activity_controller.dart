import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class ActivityViewState {
  const ActivityViewState({
    required this.date,
    this.day,
    this.week,
    this.types = const [],
    this.loading = false,
    this.stale = false,
    this.error,
    this.draft,
    this.saving = false,
    this.saveError,
  });

  final DateTime date;
  final ActivityDay? day;
  final ActivityWeek? week;
  final List<ActivityType> types;
  final bool loading;
  final bool stale;
  final String? error;
  final Map<String, dynamic>? draft;
  final bool saving;
  final String? saveError;
}

class ActivityController extends ChangeNotifier {
  ActivityController(
    this.api, {
    required this.userKey,
    required this.now,
    DateTime? initialDate,
    this.onChanged,
  }) : state = ActivityViewState(date: _dateOnly(initialDate ?? now()));

  final ApiClient api;
  final String userKey;
  final DateTime Function() now;
  final VoidCallback? onChanged;
  ActivityViewState state;
  final _dayCache = <String, ActivityDay>{};
  final _weekCache = <String, ActivityWeek>{};
  int _request = 0;
  Future<void>? _saving;
  String? _idempotencyKey;
  String? _retryRecordId;
  int _typeRequest = 0;
  bool _disposed = false;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> load(DateTime value, {bool force = false}) async {
    final date = _dateOnly(value);
    final key = formatLocalDate(date);
    final request = ++_request;
    final cachedDay = _dayCache[key];
    final cachedWeek = _weekCache[key];
    state = ActivityViewState(
      date: date,
      day: cachedDay,
      week: cachedWeek,
      types: state.types,
      loading: force || cachedDay == null || cachedWeek == null,
    );
    notifyListeners();
    if (cachedDay != null && cachedWeek != null && !force) return;
    try {
      final results = await Future.wait<Object>([
        api.getActivityDay(date),
        api.getActivityWeek(date),
      ]);
      final day = results[0] as ActivityDay;
      final week = results[1] as ActivityWeek;
      _dayCache[key] = day;
      _weekCache[key] = week;
      if (_disposed || request != _request) return;
      state = ActivityViewState(
        date: date,
        day: day,
        week: week,
        types: state.types,
        draft: state.draft,
      );
    } catch (error) {
      if (_disposed || request != _request) return;
      state = ActivityViewState(
        date: date,
        day: cachedDay,
        week: cachedWeek,
        types: state.types,
        stale: cachedDay != null || cachedWeek != null,
        error: cachedDay == null && cachedWeek == null
            ? ApiClient.errorMessage(error)
            : '数据可能不是最新',
        draft: state.draft,
      );
    }
    notifyListeners();
  }

  Future<void> refresh() => load(state.date, force: true);

  Future<List<ActivityType>> searchTypes(String query) async {
    final request = ++_typeRequest;
    try {
      final types = await api.getActivityTypes(query: query.trim());
      if (!_disposed && request == _typeRequest) {
        state = _copy(types: types, clearError: true);
        notifyListeners();
      }
      return types;
    } catch (error) {
      if (!_disposed) {
        state = _copy(error: ApiClient.errorMessage(error));
        notifyListeners();
      }
      return const [];
    }
  }

  Future<ActivityType?> createCustomType(
    String name,
    String referenceTypeId,
  ) async {
    try {
      final type = await api.createCustomActivityType(
        name: name.trim(),
        referenceTypeId: referenceTypeId,
      );
      if (!_disposed) {
        state = _copy(types: [...state.types, type], clearError: true);
        notifyListeners();
      }
      return type;
    } catch (error) {
      if (!_disposed) {
        state = _copy(saveError: ApiClient.errorMessage(error));
        notifyListeners();
      }
      return null;
    }
  }

  int? estimateKcal(
    ActivityType type,
    ActivityIntensity intensity,
    int durationMinutes,
  ) {
    final weight = state.day?.weightKg;
    if (weight == null || weight <= 0 || durationMinutes < 1) return null;
    return (type.metFor(intensity) * weight * durationMinutes / 60).round();
  }

  void saveDraft(Map<String, dynamic> draft) {
    state = _copy(
      draft: Map<String, dynamic>.from(draft),
      clearSaveError: true,
    );
    _idempotencyKey ??= _newKey();
    notifyListeners();
  }

  Future<void> save(Map<String, dynamic> draft, {String? recordId}) {
    final active = _saving;
    if (active != null) return active;
    saveDraft(draft);
    _retryRecordId = recordId;
    final body = Map<String, dynamic>.from(draft)
      ..putIfAbsent('date', () => formatLocalDate(state.date));
    final operation = _write(
      () => recordId == null
          ? api.addActivityRecord(body, idempotencyKey: _idempotencyKey!)
          : api.updateActivityRecord(recordId, body),
      clearDraft: true,
    );
    _saving = operation;
    return operation.whenComplete(() => _saving = null);
  }

  Future<void> retrySave() => state.draft == null
      ? Future.value()
      : save(Map<String, dynamic>.from(state.draft!), recordId: _retryRecordId);

  Future<void> delete(String id) =>
      _write(() => api.deleteActivityRecord(id), clearDraft: false);

  Future<void> _write(
    Future<ActivityWriteResult> Function() action, {
    required bool clearDraft,
  }) async {
    final operationDate = state.date;
    _request++;
    state = _copy(saving: true, clearSaveError: true);
    notifyListeners();
    try {
      final result = await action();
      _dayCache[formatLocalDate(result.day.date)] = result.day;
      _weekCache[formatLocalDate(operationDate)] = result.week;
      if (_disposed ||
          formatLocalDate(state.date) != formatLocalDate(operationDate)) {
        return;
      }
      state = ActivityViewState(
        date: operationDate,
        day: result.day,
        week: result.week,
        types: state.types,
        draft: clearDraft ? null : state.draft,
      );
      _idempotencyKey = null;
      _retryRecordId = null;
      onChanged?.call();
    } catch (error) {
      if (_disposed ||
          formatLocalDate(state.date) != formatLocalDate(operationDate)) {
        return;
      }
      state = _copy(saving: false, saveError: ApiClient.errorMessage(error));
    }
    notifyListeners();
  }

  ActivityViewState _copy({
    List<ActivityType>? types,
    Map<String, dynamic>? draft,
    bool? saving,
    String? error,
    String? saveError,
    bool clearError = false,
    bool clearSaveError = false,
  }) => ActivityViewState(
    date: state.date,
    day: state.day,
    week: state.week,
    types: types ?? state.types,
    loading: state.loading,
    stale: state.stale,
    error: clearError ? null : error ?? state.error,
    draft: draft ?? state.draft,
    saving: saving ?? state.saving,
    saveError: clearSaveError ? null : saveError ?? state.saveError,
  );

  String _newKey() =>
      '${now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _dayCache.clear();
    _weekCache.clear();
    super.dispose();
  }
}

class ActivityProviderKey {
  const ActivityProviderKey(
    this.api,
    this.userKey,
    this.initialDate, {
    this.now,
  });
  final ApiClient api;
  final String userKey;
  final DateTime initialDate;
  final DateTime? now;

  @override
  bool operator ==(Object other) =>
      other is ActivityProviderKey &&
      identical(api, other.api) &&
      userKey == other.userKey &&
      formatLocalDate(initialDate) == formatLocalDate(other.initialDate);

  @override
  int get hashCode => Object.hash(api, userKey, formatLocalDate(initialDate));
}

final activityControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ActivityController, ActivityProviderKey>(
      (ref, key) => ActivityController(
        key.api,
        userKey: key.userKey,
        initialDate: key.initialDate,
        now: () => key.now ?? DateTime.now(),
      ),
    );
