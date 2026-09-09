enum ActivityIntensity { low, medium, high }

extension ActivityIntensityValue on ActivityIntensity {
  String get wireName => name.toUpperCase();
  String get label => switch (this) {
    ActivityIntensity.low => '低',
    ActivityIntensity.medium => '中',
    ActivityIntensity.high => '高',
  };
}

enum ActivityTypeScope { system, user }

enum CalorieSource { estimated, userOverride }

enum ActivityPlanStatus {
  active,
  noPlan,
  paused,
  needsRecalculation,
  riskBlocked,
  unknown,
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

int _integer(Object? value, [int fallback = 0]) => switch (value) {
  num number => number.toInt(),
  String text => int.tryParse(text) ?? fallback,
  _ => fallback,
};

double _decimal(Object? value, [double fallback = 0]) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text) ?? fallback,
  _ => fallback,
};

DateTime _date(Object? value, [String fallback = '1970-01-01']) =>
    DateTime.tryParse(value?.toString() ?? '') ?? DateTime.parse(fallback);

class ActivityType {
  const ActivityType({
    required this.id,
    required this.name,
    required this.category,
    required this.scope,
    required this.lowMet,
    required this.mediumMet,
    required this.highMet,
    this.referenceTypeId,
  });

  factory ActivityType.fromJson(Map<String, dynamic> json) => ActivityType(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    scope: json['typeScope'] == 'USER' || json['scope'] == 'USER'
        ? ActivityTypeScope.user
        : ActivityTypeScope.system,
    lowMet: _decimal(json['lowMet'] ?? json['lowMET']),
    mediumMet: _decimal(json['mediumMet'] ?? json['mediumMET']),
    highMet: _decimal(json['highMet'] ?? json['highMET']),
    referenceTypeId:
        (json['referenceTypeId'] ?? json['referenceActivityTypeId'])
            ?.toString(),
  );

  final String id;
  final String name;
  final String category;
  final ActivityTypeScope scope;
  final double lowMet;
  final double mediumMet;
  final double highMet;
  final String? referenceTypeId;

  double metFor(ActivityIntensity intensity) => switch (intensity) {
    ActivityIntensity.low => lowMet,
    ActivityIntensity.medium => mediumMet,
    ActivityIntensity.high => highMet,
  };
}

class ActivityRecord {
  const ActivityRecord({
    required this.id,
    required this.activityTypeId,
    required this.activityName,
    required this.intensity,
    required this.durationMinutes,
    required this.occurredAt,
    required this.estimatedKcal,
    required this.finalKcal,
    required this.calorieSource,
    this.weightKgSnapshot,
    this.metSnapshot,
    this.calculationVersion,
  });

  factory ActivityRecord.fromJson(Map<String, dynamic> json) => ActivityRecord(
    id: json['id']?.toString() ?? '',
    activityTypeId:
        (json['activityTypeId'] ?? json['typeId'])?.toString() ?? '',
    activityName:
        (json['activityNameSnapshot'] ?? json['activityName'] ?? json['name'])
            ?.toString() ??
        '运动',
    intensity: switch (json['intensity']) {
      'LOW' => ActivityIntensity.low,
      'HIGH' => ActivityIntensity.high,
      _ => ActivityIntensity.medium,
    },
    durationMinutes: _integer(json['durationMinutes']),
    occurredAt: _date(json['occurredAt']),
    estimatedKcal: _integer(json['estimatedKcal']),
    finalKcal: _integer(json['finalKcal'] ?? json['kcal']),
    calorieSource: json['calorieSource'] == 'USER_OVERRIDE'
        ? CalorieSource.userOverride
        : CalorieSource.estimated,
    weightKgSnapshot: json['weightKgSnapshot'] == null
        ? null
        : _decimal(json['weightKgSnapshot']),
    metSnapshot: json['metSnapshot'] == null
        ? null
        : _decimal(json['metSnapshot']),
    calculationVersion: json['calculationVersion']?.toString(),
  );

  final String id;
  final String activityTypeId;
  final String activityName;
  final ActivityIntensity intensity;
  final int durationMinutes;
  final DateTime occurredAt;
  final int estimatedKcal;
  final int finalKcal;
  final CalorieSource calorieSource;
  final double? weightKgSnapshot;
  final double? metSnapshot;
  final String? calculationVersion;
}

class ActivityDay {
  const ActivityDay({
    required this.date,
    required this.status,
    required this.recordCount,
    required this.totalDurationMinutes,
    required this.totalKcal,
    required this.records,
    this.weightKg,
    this.cacheVersion,
  });

  factory ActivityDay.fromJson(Map<String, dynamic> json) {
    final summary = _map(json['summary']);
    final records =
        (json['records'] as List? ?? const [])
            .map((value) => ActivityRecord.fromJson(_map(value)))
            .toList(growable: false)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return ActivityDay(
      date: _date(json['date']),
      status:
          json['status']?.toString() ?? (records.isEmpty ? 'EMPTY' : 'READY'),
      recordCount: _integer(
        json['recordCount'] ?? json['activityCount'] ?? summary['recordCount'],
        records.length,
      ),
      totalDurationMinutes: _integer(
        json['totalDurationMinutes'] ??
            json['durationMinutes'] ??
            summary['durationMinutes'] ??
            summary['totalDurationMinutes'],
      ),
      totalKcal: _integer(
        json['totalKcal'] ??
            json['kcal'] ??
            summary['kcal'] ??
            summary['totalKcal'],
      ),
      weightKg: json['weightKg'] == null && json['currentWeightKg'] == null
          ? null
          : _decimal(json['weightKg'] ?? json['currentWeightKg']),
      cacheVersion: (json['cacheVersion'] ?? json['version'])?.toString(),
      records: records,
    );
  }

  final DateTime date;
  final String status;
  final int recordCount;
  final int totalDurationMinutes;
  final int totalKcal;
  final double? weightKg;
  final String? cacheVersion;
  final List<ActivityRecord> records;
}

class ActivityWeek {
  const ActivityWeek({
    required this.weekStart,
    required this.weekEnd,
    required this.exerciseDays,
    required this.durationMinutes,
    required this.totalKcal,
    required this.planStatus,
    this.targetExerciseDays,
    this.targetDurationMinutes,
  });

  factory ActivityWeek.fromJson(Map<String, dynamic> json) {
    final summary = _map(json['summary']);
    return ActivityWeek(
      weekStart: _date(json['weekStart'] ?? json['startDate']),
      weekEnd: _date(json['weekEnd'] ?? json['endDate']),
      exerciseDays: _integer(
        json['exerciseDays'] ?? json['actualExerciseDays'] ?? summary['days'],
      ),
      durationMinutes: _integer(
        json['durationMinutes'] ??
            json['actualDurationMinutes'] ??
            summary['minutes'],
      ),
      totalKcal: _integer(json['totalKcal'] ?? summary['kcal']),
      targetExerciseDays: json['targetExerciseDays'] == null
          ? null
          : _integer(json['targetExerciseDays']),
      targetDurationMinutes: json['targetDurationMinutes'] == null
          ? null
          : _integer(json['targetDurationMinutes']),
      planStatus: switch (json['planStatus'] ?? json['status']) {
        'ACTIVE' || 'READY' => ActivityPlanStatus.active,
        'NO_PLAN' || 'EMPTY' => ActivityPlanStatus.noPlan,
        'PAUSED' => ActivityPlanStatus.paused,
        'NEEDS_RECALCULATION' => ActivityPlanStatus.needsRecalculation,
        'RISK_BLOCKED' => ActivityPlanStatus.riskBlocked,
        _ => ActivityPlanStatus.unknown,
      },
    );
  }

  final DateTime weekStart;
  final DateTime weekEnd;
  final int exerciseDays;
  final int durationMinutes;
  final int totalKcal;
  final int? targetExerciseDays;
  final int? targetDurationMinutes;
  final ActivityPlanStatus planStatus;
}

class ActivityWriteResult {
  const ActivityWriteResult({required this.day, required this.week});

  factory ActivityWriteResult.fromJson(Map<String, dynamic> json) {
    final dayJson = _map(json['day'] ?? json['dailySummary']);
    final weekJson = _map(json['week'] ?? json['weeklySummary']);
    return ActivityWriteResult(
      day: ActivityDay.fromJson(dayJson.isEmpty ? json : dayJson),
      week: ActivityWeek.fromJson(weekJson),
    );
  }

  final ActivityDay day;
  final ActivityWeek week;
}
