import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';

enum PlanKind { noPlan, preview, active, paused, risk, unsupported }

class PlanData {
  const PlanData({
    required this.raw,
    required this.kind,
    required this.message,
    this.needsRecalculation = false,
  });

  factory PlanData.fromJson(Map<String, dynamic> json) {
    final status =
        (json['state'] ?? json['status'])?.toString().toUpperCase() ?? 'EMPTY';
    final kind = switch (status) {
      'PREVIEW' => PlanKind.preview,
      'ACTIVE' ||
      'NEEDS_RECALCULATION' ||
      'PENDING_RECALCULATION' => PlanKind.active,
      'PAUSED' => PlanKind.paused,
      'RISK_BLOCKED' || 'BLOCKED' => PlanKind.risk,
      'UNSUPPORTED' || 'GOAL_UNSUPPORTED' => PlanKind.unsupported,
      _ => PlanKind.noPlan,
    };
    return PlanData(
      raw: json,
      kind: kind,
      message: (json['message'] ?? (json['plan'] as Map?)?['safetyMessage'])
          ?.toString(),
      needsRecalculation:
          json['needsRecalculation'] == true ||
          status == 'NEEDS_RECALCULATION' ||
          status == 'PENDING_RECALCULATION',
    );
  }

  final Map<String, dynamic> raw;
  final PlanKind kind;
  final String? message;
  final bool needsRecalculation;

  Object? value(String key) {
    if (raw[key] != null) return raw[key];
    for (final section in ['plan', 'summary', 'targets', 'calculation']) {
      final nested = raw[section];
      if (nested is Map && nested[key] != null) return nested[key];
    }
    return null;
  }

  String? get id => value('id')?.toString() ?? raw['planId']?.toString();
  int get version =>
      (value('currentVersion') as num?)?.toInt() ??
      (value('version') as num?)?.toInt() ??
      (value('versionNumber') as num?)?.toInt() ??
      1;
  int get currentWeek => (value('currentWeek') as num?)?.toInt() ?? 1;
  int get targetKcal => (value('targetKcal') as num?)?.round() ?? 0;
  int get proteinG => (value('proteinG') as num?)?.round() ?? 0;
  int get carbsG => (value('carbsG') as num?)?.round() ?? 0;
  int get fatG => (value('fatG') as num?)?.round() ?? 0;
  int get waterMl => (value('waterMl') as num?)?.round() ?? 0;
  int get exerciseDays => (value('exerciseDays') as num?)?.round() ?? 0;
  int get exerciseMinutes => (value('exerciseMinutes') as num?)?.round() ?? 0;
  double get sleepHours => (value('sleepHours') as num?)?.toDouble() ?? 0;
  double get bmi => (value('bmi') as num?)?.toDouble() ?? 0;
  int get bmrKcal => (value('bmrKcal') as num?)?.round() ?? 0;
  int get tdeeKcal => (value('tdeeKcal') as num?)?.round() ?? 0;
  double get expectedWeeklyChangeKg =>
      (value('expectedWeeklyChangeKg') as num?)?.toDouble() ?? 0;
  String get ruleVersion => value('ruleVersion')?.toString() ?? 'FAT_LOSS_V1';
  String? get pausedAt => value('pausedAt')?.toString();
  String? get suggestedTargetDate => value('suggestedTargetDate')?.toString();

  int get minimumTargetKcal {
    final supplied = (value('minimumTargetKcal') as num?)?.toInt();
    if (supplied != null) return supplied;
    return targetKcal;
  }

  int get maximumTargetKcal {
    final supplied = (value('maximumTargetKcal') as num?)?.toInt();
    if (supplied != null) return supplied;
    final steps = ((tdeeKcal - 1 - minimumTargetKcal) / 50).floor();
    return math.max(minimumTargetKcal, minimumTargetKcal + steps * 50);
  }
}

class PlanViewState {
  const PlanViewState({this.data, this.loading = false, this.error});

  final PlanData? data;
  final bool loading;
  final String? error;

  PlanViewState copyWith({PlanData? data, bool? loading, String? error}) =>
      PlanViewState(
        data: data ?? this.data,
        loading: loading ?? this.loading,
        error: error,
      );
}

class PlanController extends ChangeNotifier {
  PlanController(this.api);

  final ApiClient api;
  PlanViewState state = const PlanViewState(loading: true);

  Future<void> load({bool autoPreview = false}) async {
    await _run(() async {
      final current = PlanData.fromJson(await api.getCurrentPlan());
      if (autoPreview && current.kind == PlanKind.noPlan) {
        return PlanData.fromJson({
          ...await api.previewPlan(),
          'status': 'PREVIEW',
        });
      }
      return current;
    });
  }

  Future<void> generate() => _run(
    () async =>
        PlanData.fromJson({...await api.previewPlan(), 'status': 'PREVIEW'}),
  );

  Future<bool> confirm(Map<String, dynamic>? adjustments) async {
    return _runAction(
      () async =>
          PlanData.fromJson(await api.createPlan(adjustments: adjustments)),
    );
  }

  Future<bool> recalculate() async => _withPlan(
    (id) async => PlanData.fromJson(
      await api.recalculatePlan(id, expectedVersion: state.data!.version),
    ),
  );

  Future<bool> pause() async =>
      _withPlan((id) async => PlanData.fromJson(await api.pausePlan(id)));

  Future<bool> resume() async =>
      _withPlan((id) async => PlanData.fromJson(await api.resumePlan(id)));

  Future<bool> adjust(Map<String, dynamic> targets) async => _withPlan(
    (id) async => PlanData.fromJson(await api.updatePlanTargets(id, targets)),
  );

  void applyPreviewAdjustments(Map<String, dynamic> targets) {
    final data = state.data;
    if (data == null || data.kind != PlanKind.preview) return;
    state = PlanViewState(
      data: PlanData.fromJson({...data.raw, ...targets, 'status': 'PREVIEW'}),
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> history() => api.getPlanHistory();

  Future<bool> _withPlan(Future<PlanData> Function(String id) operation) async {
    final id = state.data?.id;
    if (id == null) return false;
    return _runAction(() => operation(id));
  }

  Future<void> _run(Future<PlanData> Function() operation) async {
    await _runAction(operation);
  }

  Future<bool> _runAction(Future<PlanData> Function() operation) async {
    state = state.copyWith(loading: true);
    notifyListeners();
    try {
      final data = await operation();
      state = PlanViewState(data: data);
      notifyListeners();
      return true;
    } catch (error) {
      final code = ApiClient.errorCode(error);
      final blockedKind = switch (code) {
        'PLAN_RISK_BLOCKED' => PlanKind.risk,
        'PLAN_GOAL_UNSUPPORTED' => PlanKind.unsupported,
        _ => null,
      };
      final current = state.data;
      state = PlanViewState(
        data:
            blockedKind != null &&
                (current == null || current.kind == PlanKind.noPlan)
            ? PlanData(
                raw: const {},
                kind: blockedKind,
                message: ApiClient.errorMessage(error),
              )
            : current,
        error: ApiClient.errorMessage(error),
      );
      notifyListeners();
      return false;
    }
  }
}

final planControllerProvider =
    ChangeNotifierProvider.family<PlanController, ApiClient>(
      (ref, api) => PlanController(api),
    );
