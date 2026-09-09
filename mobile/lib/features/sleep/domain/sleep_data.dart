enum SleepRecordType { night, nap }

extension SleepRecordTypeText on SleepRecordType {
  String get wireName => name.toUpperCase();
  String get label => this == SleepRecordType.night ? '夜间睡眠' : '午睡/小睡';
}

enum SleepPlanStatus {
  active,
  noPlan,
  paused,
  needsRecalculation,
  riskBlocked,
  unknown,
}

const sleepTagLabels = <String, String>{
  'STRESS': '压力较大',
  'CAFFEINE': '喝了咖啡',
  'ALCOHOL': '饮酒',
  'SCREEN_TIME': '睡前使用手机',
  'NIGHT_AWAKENING': '夜间醒来',
  'NOISE': '环境嘈杂',
  'DISCOMFORT': '身体不适',
};

String sleepQualityLabel(int? score) => switch (score) {
  1 => '很差',
  2 => '较差',
  3 => '一般',
  4 => '良好',
  5 => '很好',
  _ => '未评价',
};

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
int _integer(Object? value, [int fallback = 0]) => switch (value) {
  num number => number.toInt(),
  String text => int.tryParse(text) ?? fallback,
  _ => fallback,
};
double? _nullableDecimal(Object? value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text),
  _ => null,
};
DateTime _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);

class SleepRecord {
  const SleepRecord({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.wakeLocalDate,
    required this.durationMinutes,
    required this.tags,
    this.qualityScore,
    this.note,
  });

  factory SleepRecord.fromJson(Map<String, dynamic> json) => SleepRecord(
    id: json['id']?.toString() ?? '',
    type: json['recordType'] == 'NAP' || json['type'] == 'NAP'
        ? SleepRecordType.nap
        : SleepRecordType.night,
    startedAt: _date(json['startedAt']),
    endedAt: _date(json['endedAt']),
    wakeLocalDate: _date(json['wakeLocalDate'] ?? json['date']),
    durationMinutes: _integer(json['durationMinutes']),
    qualityScore: json['qualityScore'] == null
        ? null
        : _integer(json['qualityScore']),
    tags: (json['tags'] as List? ?? const [])
        .map((value) => value is Map ? _map(value)['tagCode'] : value)
        .whereType<Object>()
        .map((value) => value.toString())
        .toList(growable: false),
    note: json['note']?.toString(),
  );

  final String id;
  final SleepRecordType type;
  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime wakeLocalDate;
  final int durationMinutes;
  final int? qualityScore;
  final List<String> tags;
  final String? note;
}

class SleepDay {
  const SleepDay({
    required this.date,
    required this.status,
    required this.records,
    required this.nightDurationMinutes,
    required this.napDurationMinutes,
    required this.planStatus,
    this.targetMinutes,
  });

  factory SleepDay.fromJson(Map<String, dynamic> json) {
    final summary = _map(json['summary']);
    final records =
        (json['records'] as List? ?? const [])
            .map((value) => SleepRecord.fromJson(_map(value)))
            .toList(growable: false)
          ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return SleepDay(
      date: _date(json['date'] ?? json['wakeLocalDate']),
      status:
          json['status']?.toString() ?? (records.isEmpty ? 'EMPTY' : 'READY'),
      records: records,
      nightDurationMinutes: _integer(
        json['nightDurationMinutes'] ?? summary['nightDurationMinutes'],
      ),
      napDurationMinutes: _integer(
        json['napDurationMinutes'] ?? summary['napDurationMinutes'],
      ),
      targetMinutes:
          json['targetMinutes'] == null && summary['targetMinutes'] == null
          ? null
          : _integer(json['targetMinutes'] ?? summary['targetMinutes']),
      planStatus: _planStatus(
        json['planState'] ?? json['planStatus'] ?? json['status'],
      ),
    );
  }

  final DateTime date;
  final String status;
  final List<SleepRecord> records;
  final int nightDurationMinutes;
  final int napDurationMinutes;
  final int? targetMinutes;
  final SleepPlanStatus planStatus;
  SleepRecord? get night => records
      .where((record) => record.type == SleepRecordType.night)
      .firstOrNull;
}

class SleepDailyPoint {
  const SleepDailyPoint({
    required this.date,
    required this.nightMinutes,
    required this.napMinutes,
  });
  factory SleepDailyPoint.fromJson(Map<String, dynamic> json) =>
      SleepDailyPoint(
        date: _date(json['date']),
        nightMinutes: _integer(
          json['nightDurationMinutes'] ?? json['nightMinutes'],
        ),
        napMinutes: _integer(json['napDurationMinutes'] ?? json['napMinutes']),
      );
  final DateTime date;
  final int nightMinutes;
  final int napMinutes;
}

class SleepWeek {
  const SleepWeek({
    required this.startDate,
    required this.endDate,
    required this.dailyPoints,
    required this.averageNightMinutes,
    required this.targetAchievedDays,
    required this.napTotalMinutes,
    required this.hasEnoughTrendData,
    required this.planStatus,
    this.averageQuality,
    this.targetMinutes,
  });

  factory SleepWeek.fromJson(Map<String, dynamic> json) {
    final summary = _map(json['summary']);
    return SleepWeek(
      startDate: _date(json['startDate'] ?? json['rangeStart']),
      endDate: _date(json['endDate'] ?? json['rangeEnd']),
      dailyPoints:
          (json['dailyPoints'] as List? ?? json['days'] as List? ?? const [])
              .map((value) => SleepDailyPoint.fromJson(_map(value)))
              .toList(growable: false),
      averageNightMinutes: _integer(
        json['averageNightDurationMinutes'] ??
            summary['averageNightDurationMinutes'],
      ),
      targetAchievedDays: _integer(
        json['targetMetDays'] ??
            json['targetAchievedDays'] ??
            summary['targetMetDays'] ??
            summary['targetAchievedDays'],
      ),
      averageQuality: _nullableDecimal(
        json['averageQuality'] ?? summary['averageQuality'],
      ),
      napTotalMinutes: _integer(
        json['napDurationMinutes'] ??
            json['napTotalMinutes'] ??
            summary['napDurationMinutes'] ??
            summary['napTotalMinutes'],
      ),
      hasEnoughTrendData:
          json['hasEnoughTrendData'] == true || json['dataStatus'] == 'ENOUGH',
      targetMinutes: json['targetMinutes'] == null
          ? null
          : _integer(json['targetMinutes']),
      planStatus: _planStatus(
        json['planState'] ?? json['planStatus'] ?? json['status'],
      ),
    );
  }

  final DateTime startDate;
  final DateTime endDate;
  final List<SleepDailyPoint> dailyPoints;
  final int averageNightMinutes;
  final int targetAchievedDays;
  final double? averageQuality;
  final int napTotalMinutes;
  final bool hasEnoughTrendData;
  final int? targetMinutes;
  final SleepPlanStatus planStatus;
}

SleepPlanStatus _planStatus(Object? value) => switch (value) {
  'ACTIVE' || 'READY' => SleepPlanStatus.active,
  'NO_PLAN' || 'EMPTY' => SleepPlanStatus.noPlan,
  'PAUSED' => SleepPlanStatus.paused,
  'NEEDS_RECALCULATION' => SleepPlanStatus.needsRecalculation,
  'RISK_BLOCKED' => SleepPlanStatus.riskBlocked,
  _ => SleepPlanStatus.unknown,
};

class SleepWriteResult {
  const SleepWriteResult({required this.day, required this.week});
  factory SleepWriteResult.fromJson(Map<String, dynamic> json) =>
      SleepWriteResult(
        day: SleepDay.fromJson(_map(json['day'] ?? json['dailySummary'])),
        week: SleepWeek.fromJson(_map(json['week'] ?? json['weeklySummary'])),
      );
  final SleepDay day;
  final SleepWeek week;
}
