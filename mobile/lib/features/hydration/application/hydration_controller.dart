import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class HydrationViewState {
  const HydrationViewState({
    required this.date,
    this.data,
    this.loading = false,
    this.stale = false,
    this.error,
    this.saving = false,
    this.saveError,
    this.retryAmountMl,
    this.settingsDraft,
  });
  final DateTime date;
  final HydrationDay? data;
  final bool loading;
  final bool stale;
  final String? error;
  final bool saving;
  final String? saveError;
  final int? retryAmountMl;
  final Map<String, dynamic>? settingsDraft;
}

class HydrationController extends ChangeNotifier {
  HydrationController(
    this.api, {
    required this.userKey,
    required this.now,
    required this.timezone,
    this.syncReminders,
    DateTime? initialDate,
  }) : state = HydrationViewState(date: _date(initialDate ?? now()));
  final ApiClient api;
  final String userKey;
  final DateTime Function() now;
  final Future<String> Function() timezone;
  final Future<void> Function(HydrationDay)? syncReminders;
  HydrationViewState state;
  final _cache = <String, HydrationDay>{};
  int _request = 0;
  bool _disposed = false;
  String? _retryKey;
  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);
  Future<void> load(DateTime value, {bool force = false}) async {
    final date = _date(value),
        key = formatLocalDate(date),
        request = ++_request,
        cached = _cache[key];
    state = HydrationViewState(
      date: date,
      data: cached,
      loading: force || cached == null,
    );
    notifyListeners();
    if (cached != null && !force) return;
    try {
      final data = await api.getHydrationDay(date, timezone: await timezone());
      _cache[key] = data;
      await _sync(data);
      if (_disposed || request != _request) return;
      state = HydrationViewState(date: date, data: data);
    } catch (e) {
      if (_disposed || request != _request) return;
      state = HydrationViewState(
        date: date,
        data: cached,
        stale: cached != null,
        error: cached == null ? ApiClient.errorMessage(e) : '数据可能不是最新',
      );
    }
    notifyListeners();
  }

  Future<void> refresh() => load(state.date, force: true);
  Future<void> add(int amount, {String source = 'QUICK'}) async {
    if (amount < 1 || amount > 3000) return;
    final date = state.date, original = state.data;
    _request++;
    _retryKey ??=
        '${now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    state = HydrationViewState(
      date: date,
      data: original?.optimistic(amount),
      saving: true,
    );
    notifyListeners();
    try {
      final data = await api.addHydrationEntry({
        'amountMl': amount,
        'occurredAt': DateTime(
          date.year,
          date.month,
          date.day,
          now().hour,
          now().minute,
          now().second,
        ).toIso8601String(),
        'timezone': await timezone(),
        'source': source,
      }, idempotencyKey: _retryKey!);
      _cache[formatLocalDate(data.date)] = data;
      await _sync(data);
      if (_disposed || formatLocalDate(state.date) != formatLocalDate(date)) {
        return;
      }
      state = HydrationViewState(date: date, data: data);
      _retryKey = null;
    } catch (e) {
      if (_disposed || formatLocalDate(state.date) != formatLocalDate(date)) {
        return;
      }
      state = HydrationViewState(
        date: date,
        data: original,
        saveError: ApiClient.errorMessage(e),
        retryAmountMl: amount,
      );
    }
    notifyListeners();
  }

  Future<void> retry() =>
      state.retryAmountMl == null ? Future.value() : add(state.retryAmountMl!);
  Future<void> delete(String id) async {
    try {
      final data = await api.deleteHydrationEntry(
        id,
        timezone: await timezone(),
      );
      _cache[formatLocalDate(data.date)] = data;
      await _sync(data);
      state = HydrationViewState(date: state.date, data: data);
    } catch (e) {
      state = HydrationViewState(
        date: state.date,
        data: state.data,
        saveError: ApiClient.errorMessage(e),
      );
    }
    notifyListeners();
  }

  void setSettingsDraft(Map<String, dynamic> value) {
    state = HydrationViewState(
      date: state.date,
      data: state.data,
      settingsDraft: Map.of(value),
    );
    notifyListeners();
  }

  Future<void> _sync(HydrationDay day) async {
    try {
      await syncReminders?.call(day);
    } catch (_) {
      // Notification failures never block authoritative hydration data.
    }
  }

  Future<void> saveSettings() async {
    final draft = state.settingsDraft;
    if (draft == null) return;
    try {
      await api.updateHydrationSettings(draft);
      await refresh();
    } catch (e) {
      if (ApiClient.errorCode(e) == 'HYDRATION_SETTINGS_VERSION_CONFLICT') {
        await refresh();
      }
      state = HydrationViewState(
        date: state.date,
        data: state.data,
        saveError: ApiClient.errorMessage(e),
        settingsDraft: draft,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cache.clear();
    super.dispose();
  }
}

class HydrationProviderKey {
  const HydrationProviderKey(
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
      other is HydrationProviderKey &&
      identical(api, other.api) &&
      userKey == other.userKey &&
      formatLocalDate(initialDate) == formatLocalDate(other.initialDate);
  @override
  int get hashCode => Object.hash(api, userKey, formatLocalDate(initialDate));
}

final hydrationControllerProvider = ChangeNotifierProvider.autoDispose
    .family<HydrationController, HydrationProviderKey>(
      (ref, key) => HydrationController(
        key.api,
        userKey: key.userKey,
        initialDate: key.initialDate,
        now: () => key.today ?? DateTime.now(),
        timezone: HydrationReminderScheduler.instance.timezoneName,
        syncReminders: (day) =>
            formatLocalDate(day.date) ==
                formatLocalDate(key.today ?? DateTime.now())
            ? HydrationReminderScheduler.instance.sync(
                accountKey: key.userKey,
                day: day,
              )
            : Future.value(),
      ),
    );
