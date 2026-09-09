String formatLocalDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

enum TodayModuleStatus {
  ready,
  empty,
  comingSoon,
  profileIncomplete,
  noPlan,
  paused,
  needsRecalculation,
  riskBlocked,
  error,
}

TodayModuleStatus _status(Object? value) => switch (value) {
  'READY' => TodayModuleStatus.ready,
  'EMPTY' => TodayModuleStatus.empty,
  'COMING_SOON' => TodayModuleStatus.comingSoon,
  'PROFILE_INCOMPLETE' => TodayModuleStatus.profileIncomplete,
  'NO_PLAN' => TodayModuleStatus.noPlan,
  'PAUSED' => TodayModuleStatus.paused,
  'NEEDS_RECALCULATION' => TodayModuleStatus.needsRecalculation,
  'RISK_BLOCKED' => TodayModuleStatus.riskBlocked,
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
  const TodayModuleData({
    required this.status,
    this.message,
    this.consumedKcal,
    this.targetKcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.consumedMl,
    this.targetMl,
    this.remainingMl,
    this.progress,
    this.todayDurationMinutes,
    this.todayKcal,
    this.todayRecordCount,
    this.weekExerciseDays,
    this.weekDurationMinutes,
    this.targetExerciseDays,
    this.targetDurationMinutes,
    this.nightDurationMinutes,
    this.targetMinutes,
    this.differenceMinutes,
    this.qualityScore,
    this.qualityLabel,
    this.napDurationMinutes,
    this.hasEnoughTrendData,
  });

  factory TodayModuleData.fromJson(Map<String, dynamic> json) =>
      TodayModuleData(
        status: _status(json['status']),
        message: json['message']?.toString(),
        consumedKcal: (json['consumedKcal'] as num?)?.toInt(),
        targetKcal: (json['targetKcal'] as num?)?.toInt(),
        proteinG: (json['proteinG'] as num?)?.toDouble(),
        carbsG: (json['carbsG'] as num?)?.toDouble(),
        fatG: (json['fatG'] as num?)?.toDouble(),
        consumedMl: (json['consumedMl'] as num?)?.toInt(),
        targetMl: (json['targetMl'] as num?)?.toInt(),
        remainingMl: (json['remainingMl'] as num?)?.toInt(),
        progress: (json['progress'] as num?)?.toDouble(),
        todayDurationMinutes: (json['todayDurationMinutes'] as num?)?.toInt(),
        todayKcal: (json['todayKcal'] as num?)?.toInt(),
        todayRecordCount: (json['todayRecordCount'] as num?)?.toInt(),
        weekExerciseDays: (json['weekExerciseDays'] as num?)?.toInt(),
        weekDurationMinutes: (json['weekDurationMinutes'] as num?)?.toInt(),
        targetExerciseDays: (json['targetExerciseDays'] as num?)?.toInt(),
        targetDurationMinutes: (json['targetDurationMinutes'] as num?)?.toInt(),
        nightDurationMinutes: (json['nightDurationMinutes'] as num?)?.toInt(),
        targetMinutes: (json['targetMinutes'] as num?)?.toInt(),
        differenceMinutes: (json['differenceMinutes'] as num?)?.toInt(),
        qualityScore: (json['qualityScore'] as num?)?.toInt(),
        qualityLabel: json['qualityLabel']?.toString(),
        napDurationMinutes: (json['napDurationMinutes'] as num?)?.toInt(),
        hasEnoughTrendData: json['hasEnoughTrendData'] as bool?,
      );

  final TodayModuleStatus status;
  final String? message;
  final int? consumedKcal;
  final int? targetKcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final int? consumedMl;
  final int? targetMl;
  final int? remainingMl;
  final double? progress;
  final int? todayDurationMinutes;
  final int? todayKcal;
  final int? todayRecordCount;
  final int? weekExerciseDays;
  final int? weekDurationMinutes;
  final int? targetExerciseDays;
  final int? targetDurationMinutes;
  final int? nightDurationMinutes;
  final int? targetMinutes;
  final int? differenceMinutes;
  final int? qualityScore;
  final String? qualityLabel;
  final int? napDurationMinutes;
  final bool? hasEnoughTrendData;
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
