import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class TodayViewState {
  const TodayViewState({
    this.data,
    this.requestedDate,
    this.loading = false,
    this.stale = false,
    this.error,
  });

  final TodayData? data;
  final DateTime? requestedDate;
  final bool loading;
  final bool stale;
  final String? error;
}

class TodayController extends ChangeNotifier {
  TodayController(this.api);

  final ApiClient api;
  TodayViewState state = const TodayViewState();
  Future<void>? _loading;
  bool _disposed = false;

  Future<void> load(DateTime date) {
    final active = _loading;
    if (active != null) {
      final requested = state.requestedDate;
      if (requested != null &&
          formatLocalDate(requested) == formatLocalDate(date)) {
        return active;
      }
      return active.then((_) => load(date));
    }
    final operation = _load(date);
    _loading = operation;
    return operation.whenComplete(() => _loading = null);
  }

  Future<void> refresh() {
    final date = state.requestedDate;
    return date == null ? Future.value() : load(date);
  }

  Future<void> _load(DateTime date) async {
    final sameDate =
        state.data != null &&
        formatLocalDate(state.data!.date) == formatLocalDate(date);
    state = TodayViewState(
      data: sameDate ? state.data : null,
      requestedDate: date,
      loading: true,
    );
    notifyListeners();
    try {
      final data = await api.getToday(date);
      if (_disposed) return;
      state = TodayViewState(data: data, requestedDate: date);
    } catch (error) {
      if (_disposed) return;
      final cached = state.data;
      state = TodayViewState(
        data: cached,
        requestedDate: date,
        stale: cached != null,
        error: cached == null
            ? ApiClient.errorMessage(error)
            : '刷新失败，当前内容可能不是最新',
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final todayControllerProvider = ChangeNotifierProvider.autoDispose
    .family<TodayController, ApiClient>((ref, api) => TodayController(api));
