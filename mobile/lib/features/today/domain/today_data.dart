String formatLocalDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

enum TodayModuleStatus { ready, empty, comingSoon, error }

TodayModuleStatus _status(Object? value) => switch (value) {
  'READY' => TodayModuleStatus.ready,
  'EMPTY' => TodayModuleStatus.empty,
  'COMING_SOON' => TodayModuleStatus.comingSoon,
  'ERROR' => TodayModuleStatus.error,
  _ => TodayModuleStatus.error,
};

enum TodayNextActionType {
  completeProfile,
  createPlan,
  confirmPlan,
  resumePlan,
  viewPlan,
  viewRiskGuidance,
  unknown,
}

TodayNextActionType _action(Object? value) => switch (value) {
  'COMPLETE_PROFILE' => TodayNextActionType.completeProfile,
  'CREATE_PLAN' => TodayNextActionType.createPlan,
  'CONFIRM_PLAN' => TodayNextActionType.confirmPlan,
  'RESUME_PLAN' => TodayNextActionType.resumePlan,
  'VIEW_PLAN' => TodayNextActionType.viewPlan,
  'VIEW_RISK_GUIDANCE' => TodayNextActionType.viewRiskGuidance,
  _ => TodayNextActionType.unknown,
};

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

class TodayData {
  const TodayData({
    required this.date,
    required this.plan,
    required this.weight,
    required this.nutrition,
    required this.hydration,
    required this.activity,
    required this.sleep,
    required this.tasks,
    required this.nextAction,
  });

  factory TodayData.fromJson(Map<String, dynamic> json) => TodayData(
    date: DateTime.parse(json['date'] as String),
    plan: TodayPlanData.fromJson(_map(json['plan'])),
    weight: TodayWeightData.fromJson(_map(json['weight'])),
    nutrition: TodayModuleData.fromJson(_map(json['nutrition'])),
    hydration: TodayModuleData.fromJson(_map(json['hydration'])),
    activity: TodayModuleData.fromJson(_map(json['activity'])),
    sleep: TodayModuleData.fromJson(_map(json['sleep'])),
    tasks: TodayModuleData.fromJson(_map(json['tasks'])),
    nextAction: TodayNextAction.fromJson(_map(json['nextAction'])),
  );

  final DateTime date;
  final TodayPlanData plan;
  final TodayWeightData weight;
  final TodayModuleData nutrition;
  final TodayModuleData hydration;
  final TodayModuleData activity;
  final TodayModuleData sleep;
  final TodayModuleData tasks;
  final TodayNextAction nextAction;
}

class TodayPlanData {
  const TodayPlanData({
    required this.status,
    required this.state,
    this.currentWeek,
    this.targetKcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.waterMl,
    this.exerciseDays,
    this.exerciseMinutes,
    this.sleepHours,
    this.message,
  });

  factory TodayPlanData.fromJson(Map<String, dynamic> json) => TodayPlanData(
    status: _status(json['status']),
    state: json['state']?.toString() ?? 'ERROR',
    currentWeek: (json['currentWeek'] as num?)?.toInt(),
    targetKcal: (json['targetKcal'] as num?)?.toInt(),
    proteinG: (json['proteinG'] as num?)?.toInt(),
    carbsG: (json['carbsG'] as num?)?.toInt(),
    fatG: (json['fatG'] as num?)?.toInt(),
    waterMl: (json['waterMl'] as num?)?.toInt(),
    exerciseDays: (json['exerciseDays'] as num?)?.toInt(),
    exerciseMinutes: (json['exerciseMinutes'] as num?)?.toInt(),
    sleepHours: (json['sleepHours'] as num?)?.toDouble(),
    message: json['message']?.toString(),
  );

  final TodayModuleStatus status;
  final String state;
  final int? currentWeek;
  final int? targetKcal;
  final int? proteinG;
  final int? carbsG;
  final int? fatG;
  final int? waterMl;
  final int? exerciseDays;
  final int? exerciseMinutes;
  final double? sleepHours;
  final String? message;
}

class TodayWeightData {
  const TodayWeightData({
    required this.status,
    this.valueKg,
    this.measuredAt,
    this.message,
  });

  factory TodayWeightData.fromJson(Map<String, dynamic> json) =>
      TodayWeightData(
        status: _status(json['status']),
        valueKg: (json['valueKg'] as num?)?.toDouble(),
        measuredAt: json['measuredAt'] == null
            ? null
            : DateTime.tryParse(json['measuredAt'].toString()),
        message: json['message']?.toString(),
      );

  final TodayModuleStatus status;
  final double? valueKg;
  final DateTime? measuredAt;
  final String? message;
}

class TodayModuleData {
  const TodayModuleData({required this.status, this.message});

  factory TodayModuleData.fromJson(Map<String, dynamic> json) =>
      TodayModuleData(
        status: _status(json['status']),
        message: json['message']?.toString(),
      );

  final TodayModuleStatus status;
  final String? message;
}

class TodayNextAction {
  const TodayNextAction({required this.type, required this.title});

  factory TodayNextAction.fromJson(Map<String, dynamic> json) =>
      TodayNextAction(
        type: _action(json['type']),
        title: json['title']?.toString() ?? '查看今日安排',
      );

  final TodayNextActionType type;
  final String title;
}
