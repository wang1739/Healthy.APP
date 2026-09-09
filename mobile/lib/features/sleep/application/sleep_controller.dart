import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class SleepViewState {
  const SleepViewState({
    required this.date,
    this.day,
    this.week,
    this.loading = false,
    this.stale = false,
    this.error,
    this.draft,
    this.saving = false,
    this.saveError,
  });
  final DateTime date;
  final SleepDay? day;
  final SleepWeek? week;
  final bool loading;
  final bool stale;
  final String? error;
  final Map<String, dynamic>? draft;
  final bool saving;
  final String? saveError;
}

class SleepController extends ChangeNotifier {
  SleepController(
    this.api, {
    required this.userKey,
    required this.now,
    DateTime? initialDate,
  }) : state = SleepViewState(date: _dateOnly(initialDate ?? now()));
  final ApiClient api;
  final String userKey;
  final DateTime Function() now;
  SleepViewState state;
  final _dayCache = <String, SleepDay>{};
  final _weekCache = <String, SleepWeek>{};
  int _request = 0;
  bool _disposed = false;
  Future<void>? _saving;
  String? _idempotencyKey;
  String? _retryRecordId;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> load(DateTime value, {bool force = false}) async {
    final date = _dateOnly(value);
    final key = formatLocalDate(date);
    final request = ++_request;
    final cachedDay = _dayCache[key];
    final cachedWeek = _weekCache[key];
    state = SleepViewState(
      date: date,
      day: cachedDay,
      week: cachedWeek,
      loading: force || cachedDay == null || cachedWeek == null,
      draft: state.draft,
    );
    notifyListeners();
    if (cachedDay != null && cachedWeek != null && !force) return;
    try {
      final results = await Future.wait<Object>([
        api.getSleepDay(date),
        api.getSleepWeek(date),
      ]);
      final day = results[0] as SleepDay;
      final week = results[1] as SleepWeek;
      _dayCache[key] = day;
      _weekCache[key] = week;
      if (_disposed || request != _request) return;
      state = SleepViewState(
        date: date,
        day: day,
        week: week,
        draft: state.draft,
      );
    } catch (error) {
      if (_disposed || request != _request) return;
      state = SleepViewState(
        date: date,
        day: cachedDay,
        week: cachedWeek,
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

  void saveDraft(Map<String, dynamic> draft) {
    state = _copy(
      draft: Map<String, dynamic>.from(draft),
      clearSaveError: true,
    );
    _idempotencyKey ??=
        '${now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    notifyListeners();
  }

  Future<void> save(Map<String, dynamic> draft, {String? recordId}) {
    if (_saving != null) return _saving!;
    saveDraft(draft);
    _retryRecordId = recordId;
    final operation = _write(
      () => recordId == null
          ? api.addSleepRecord(draft, idempotencyKey: _idempotencyKey!)
          : api.updateSleepRecord(recordId, draft),
      clearDraft: true,
    );
    _saving = operation;
    return operation.whenComplete(() => _saving = null);
  }

  Future<void> retrySave() => state.draft == null
      ? Future.value()
      : save(Map<String, dynamic>.from(state.draft!), recordId: _retryRecordId);

  Future<void> delete(String id) =>
      _write(() => api.deleteSleepRecord(id), clearDraft: false);

  Future<void> _write(
    Future<SleepWriteResult> Function() action, {
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
      state = SleepViewState(
        date: operationDate,
        day: result.day,
        week: result.week,
        draft: clearDraft ? null : state.draft,
      );
      _idempotencyKey = null;
      _retryRecordId = null;
    } catch (error) {
      if (_disposed ||
          formatLocalDate(state.date) != formatLocalDate(operationDate)) {
        return;
      }
      state = _copy(saving: false, saveError: ApiClient.errorMessage(error));
    }
    notifyListeners();
  }

  SleepViewState _copy({
    Map<String, dynamic>? draft,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
  }) => SleepViewState(
    date: state.date,
    day: state.day,
    week: state.week,
    loading: state.loading,
    stale: state.stale,
    error: state.error,
    draft: draft ?? state.draft,
    saving: saving ?? state.saving,
    saveError: clearSaveError ? null : saveError ?? state.saveError,
  );

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _dayCache.clear();
    _weekCache.clear();
    super.dispose();
  }
}

class SleepProviderKey {
  const SleepProviderKey(this.api, this.userKey, this.initialDate, {this.now});
  final ApiClient api;
  final String userKey;
  final DateTime initialDate;
  final DateTime? now;
  @override
  bool operator ==(Object other) =>
      other is SleepProviderKey &&
      identical(api, other.api) &&
      userKey == other.userKey &&
      formatLocalDate(initialDate) == formatLocalDate(other.initialDate);
  @override
  int get hashCode => Object.hash(api, userKey, formatLocalDate(initialDate));
}

final sleepControllerProvider = ChangeNotifierProvider.autoDispose
    .family<SleepController, SleepProviderKey>(
      (ref, key) => SleepController(
        key.api,
        userKey: key.userKey,
        initialDate: key.initialDate,
        now: () => key.now ?? DateTime.now(),
      ),
    );
