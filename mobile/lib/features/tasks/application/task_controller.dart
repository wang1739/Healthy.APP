import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskViewState {
  const TaskViewState({
    required this.date,
    this.day,
    this.week,
    this.filter,
    this.loading = false,
    this.stale = false,
    this.error,
    this.draft,
    this.saving = false,
    this.saveError,
    this.actionError,
    this.busyIds = const {},
  });
  final DateTime date;
  final TaskDay? day;
  final TaskWeek? week;
  final TaskCategory? filter;
  final bool loading;
  final bool stale;
  final String? error;
  final Map<String, dynamic>? draft;
  final bool saving;
  final String? saveError;
  final String? actionError;
  final Set<String> busyIds;
}

enum TaskEditScope { instance, template }

class TaskController extends ChangeNotifier {
  TaskController(
    this.api, {
    required this.accountKey,
    required this.now,
    DateTime? initialDate,
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       state = TaskViewState(date: _dayOnly(initialDate ?? now()));

  final ApiClient api;
  final String accountKey;
  final DateTime Function() now;
  final Future<SharedPreferences> Function() _preferences;
  TaskViewState state;
  final _dayCache = <String, TaskDay>{};
  final _weekCache = <String, TaskWeek>{};
  int _request = 0;
  bool _disposed = false;
  Future<void>? _saving;
  String? _saveKey;
  String? _retryInstanceId;
  String? _retryTemplateId;
  TaskEditScope _retryScope = TaskEditScope.instance;
  Future<void> Function()? _retryAction;

  static DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  String _key(DateTime date) => formatLocalDate(date);
  String _storageKey(DateTime date) =>
      'task_day_${accountKey}_${formatLocalDate(date)}';

  List<TaskInstance> get visibleTasks {
    final tasks = state.day?.allTasks ?? const <TaskInstance>[];
    return state.filter == null
        ? tasks
        : tasks.where((task) => task.category == state.filter).toList();
  }

  void filter(TaskCategory? value) {
    state = _copy(filter: value, replaceFilter: true);
    notifyListeners();
  }

  Future<void> load(DateTime value, {bool force = false}) async {
    final date = _dayOnly(value);
    final key = _key(date);
    final request = ++_request;
    var cachedDay = _dayCache[key];
    final cachedWeek = _weekCache[key];
    if (cachedDay == null) {
      try {
        final raw = (await _preferences()).getString(_storageKey(date));
        if (raw != null) cachedDay = TaskDay.fromJson(jsonDecode(raw));
      } catch (_) {
        // A broken local cache must never block authoritative loading.
      }
    }
    if (_disposed || request != _request) return;
    state = TaskViewState(
      date: date,
      day: cachedDay,
      week: cachedWeek,
      filter: state.filter,
      loading: force || cachedDay == null || cachedWeek == null,
      stale: cachedDay != null,
      draft: state.draft,
    );
    notifyListeners();
    if (!force && cachedDay != null && cachedWeek != null) return;
    try {
      final values = await Future.wait<Object>([
        api.getTaskDay(date),
        api.getTaskWeek(date),
      ]);
      final day = values[0] as TaskDay;
      final week = values[1] as TaskWeek;
      _dayCache[key] = day;
      _weekCache[key] = week;
      await _saveCache(day);
      if (_disposed || request != _request) return;
      state = TaskViewState(
        date: date,
        day: day,
        week: week,
        filter: state.filter,
        draft: state.draft,
      );
    } catch (error) {
      if (_disposed || request != _request) return;
      state = TaskViewState(
        date: date,
        day: cachedDay,
        week: cachedWeek,
        filter: state.filter,
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
    _saveKey ??= _idempotencyKey();
    notifyListeners();
  }

  Future<void> save(
    Map<String, dynamic> draft, {
    String? instanceId,
    String? templateId,
    TaskEditScope scope = TaskEditScope.instance,
  }) {
    if (_saving != null) return _saving!;
    saveDraft(draft);
    _retryInstanceId = instanceId;
    _retryTemplateId = templateId;
    _retryScope = scope;
    final operation = _save(
      draft,
      instanceId: instanceId,
      templateId: templateId,
      scope: scope,
    );
    _saving = operation;
    return operation.whenComplete(() => _saving = null);
  }

  Future<void> _save(
    Map<String, dynamic> draft, {
    String? instanceId,
    String? templateId,
    required TaskEditScope scope,
  }) async {
    state = _copy(saving: true, clearSaveError: true);
    notifyListeners();
    try {
      final result = instanceId == null
          ? await api.createTask(draft, idempotencyKey: _saveKey!)
          : scope == TaskEditScope.template && templateId != null
          ? await api.updateTaskTemplate(templateId, draft)
          : await api.updateTaskInstance(instanceId, draft);
      await _applyResult(result);
      state = _copy(saving: false, clearDraft: true, clearSaveError: true);
      _saveKey = null;
      _retryInstanceId = null;
      _retryTemplateId = null;
    } catch (error) {
      if (_disposed) return;
      state = _copy(saving: false, saveError: ApiClient.errorMessage(error));
    }
    notifyListeners();
  }

  Future<void> retrySave() => state.draft == null
      ? Future.value()
      : save(
          Map<String, dynamic>.from(state.draft!),
          instanceId: _retryInstanceId,
          templateId: _retryTemplateId,
          scope: _retryScope,
        );

  Future<void> complete(String id) => _statusAction(
    id,
    TaskStatus.completed,
    (key) => api.completeTask(id, idempotencyKey: key),
  );

  Future<void> reopen(String id) => _statusAction(
    id,
    TaskStatus.pending,
    (key) => api.reopenTask(id, idempotencyKey: key),
  );

  Future<void> skip(String id, {String? reason}) => _statusAction(
    id,
    TaskStatus.skipped,
    (key) => api.skipTask(id, idempotencyKey: key, reason: reason),
  );

  Future<void> postpone(String id, Map<String, dynamic> data) => _statusAction(
    id,
    TaskStatus.pending,
    (key) => api.postponeTask(id, data, idempotencyKey: key),
    postpone: true,
  );

  Future<void> _statusAction(
    String id,
    TaskStatus optimistic,
    Future<TaskMutationResult> Function(String key) action, {
    bool postpone = false,
    String? key,
  }) async {
    if (state.busyIds.contains(id)) return;
    final before = state.day;
    final task = before?.byId(id);
    if (before == null || task == null) return;
    final actionKey = key ?? _idempotencyKey();
    _request++;
    final updated = task.copyWith(
      status: optimistic,
      postponeCount: postpone ? task.postponeCount + 1 : task.postponeCount,
    );
    state = _copy(
      day: before.replace(updated),
      busyIds: {...state.busyIds, id},
      clearActionError: true,
    );
    notifyListeners();
    try {
      final result = await action(actionKey);
      if (_disposed) return;
      await _applyResult(result);
      _retryAction = null;
      state = _copy(
        busyIds: {...state.busyIds}..remove(id),
        clearActionError: true,
      );
    } catch (error) {
      if (_disposed) return;
      _retryAction = () => _statusAction(
        id,
        optimistic,
        action,
        postpone: postpone,
        key: actionKey,
      );
      state = _copy(
        day: before,
        busyIds: {...state.busyIds}..remove(id),
        actionError: '${ApiClient.errorMessage(error)}，可重试',
      );
    }
    notifyListeners();
  }

  Future<void> retryAction() => _retryAction?.call() ?? Future.value();

  Future<void> deleteInstance(String id) async {
    await api.deleteTaskInstance(id);
    await refresh();
    notifyListeners();
  }

  Future<void> deleteTemplate(String id, DateTime effectiveDate) async {
    await api.deleteTaskTemplate(id, effectiveDate: effectiveDate);
    await refresh();
    notifyListeners();
  }

  Future<void> _applyResult(TaskMutationResult result) async {
    if (_disposed) return;
    final day = result.day ?? state.day?.replace(result.instance);
    if (day == null) return;
    final key = _key(day.date);
    _dayCache[key] = day;
    if (_key(state.date) == key) state = _copy(day: day);
    await _saveCache(day);
  }

  Future<void> _saveCache(TaskDay day) async {
    try {
      final prefs = await _preferences();
      await prefs.setString(_storageKey(day.date), jsonEncode(day.toJson()));
    } catch (_) {
      // Cache persistence is best-effort; the server remains authoritative.
    }
  }

  String _idempotencyKey() =>
      '${now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  TaskViewState _copy({
    TaskDay? day,
    TaskWeek? week,
    TaskCategory? filter,
    bool replaceFilter = false,
    Map<String, dynamic>? draft,
    bool clearDraft = false,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
    String? actionError,
    bool clearActionError = false,
    Set<String>? busyIds,
  }) => TaskViewState(
    date: state.date,
    day: day ?? state.day,
    week: week ?? state.week,
    filter: replaceFilter ? filter : state.filter,
    loading: state.loading,
    stale: state.stale,
    error: state.error,
    draft: clearDraft ? null : draft ?? state.draft,
    saving: saving ?? state.saving,
    saveError: clearSaveError ? null : saveError ?? state.saveError,
    actionError: clearActionError ? null : actionError ?? state.actionError,
    busyIds: busyIds ?? state.busyIds,
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

class TaskProviderKey {
  const TaskProviderKey(
    this.api,
    this.accountKey,
    this.initialDate, {
    this.now,
  });
  final ApiClient api;
  final String accountKey;
  final DateTime initialDate;
  final DateTime? now;
  @override
  bool operator ==(Object other) =>
      other is TaskProviderKey &&
      identical(api, other.api) &&
      accountKey == other.accountKey &&
      formatLocalDate(initialDate) == formatLocalDate(other.initialDate);
  @override
  int get hashCode =>
      Object.hash(api, accountKey, formatLocalDate(initialDate));
}

final taskControllerProvider = ChangeNotifierProvider.autoDispose
    .family<TaskController, TaskProviderKey>(
      (ref, key) => TaskController(
        key.api,
        accountKey: key.accountKey,
        initialDate: key.initialDate,
        now: () => key.now ?? DateTime.now(),
      ),
    );
