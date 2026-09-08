Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

enum HydrationTargetSource { user, plan, defaultTarget }

HydrationTargetSource _source(Object? value) => switch (value) {
  'USER' => HydrationTargetSource.user,
  'PLAN' => HydrationTargetSource.plan,
  _ => HydrationTargetSource.defaultTarget,
};

class HydrationSettings {
  const HydrationSettings({
    required this.defaultCupMl,
    required this.effectiveTargetMl,
    required this.version,
    required this.reminderEnabled,
    required this.reminderStart,
    required this.reminderEnd,
    required this.reminderIntervalMinutes,
    this.dailyTargetMl,
    this.quietStart,
    this.quietEnd,
    this.planTargetMl,
    this.planTargetChanged = false,
    this.targetSource = HydrationTargetSource.defaultTarget,
  });
  factory HydrationSettings.fromJson(Map<String, dynamic> json) =>
      HydrationSettings(
        dailyTargetMl: (json['dailyTargetMl'] as num?)?.toInt(),
        effectiveTargetMl:
            (json['effectiveTargetMl'] as num?)?.toInt() ??
            (json['targetMl'] as num?)?.toInt() ??
            2000,
        defaultCupMl: (json['defaultCupMl'] as num?)?.toInt() ?? 250,
        reminderEnabled: json['reminderEnabled'] == true,
        reminderStart: json['reminderStartTime']?.toString() ?? '08:00',
        reminderEnd: json['reminderEndTime']?.toString() ?? '20:00',
        reminderIntervalMinutes:
            (json['reminderIntervalMinutes'] as num?)?.toInt() ?? 120,
        quietStart: json['quietStartTime']?.toString(),
        quietEnd: json['quietEndTime']?.toString(),
        planTargetMl: (json['planTargetMl'] as num?)?.toInt(),
        planTargetChanged: json['planTargetChanged'] == true,
        targetSource: _source(json['targetSource']),
        version: (json['version'] as num?)?.toInt() ?? 0,
      );
  final int? dailyTargetMl;
  final int effectiveTargetMl;
  final int defaultCupMl;
  final bool reminderEnabled;
  final String reminderStart;
  final String reminderEnd;
  final int reminderIntervalMinutes;
  final String? quietStart;
  final String? quietEnd;
  final int? planTargetMl;
  final bool planTargetChanged;
  final HydrationTargetSource targetSource;
  final int version;
  Map<String, dynamic> toJson() => {
    'dailyTargetMl': dailyTargetMl,
    'defaultCupMl': defaultCupMl,
    'reminderEnabled': reminderEnabled,
    'reminderStartTime': reminderStart,
    'reminderEndTime': reminderEnd,
    'reminderIntervalMinutes': reminderIntervalMinutes,
    'quietStartTime': quietStart,
    'quietEndTime': quietEnd,
    'version': version,
  };
}

class HydrationEntry {
  const HydrationEntry({
    required this.id,
    required this.amountMl,
    required this.occurredAt,
    required this.source,
  });
  factory HydrationEntry.fromJson(Map<String, dynamic> json) => HydrationEntry(
    id: json['id']?.toString() ?? '',
    amountMl: (json['amountMl'] as num?)?.toInt() ?? 0,
    occurredAt: DateTime.parse(json['occurredAt'].toString()),
    source: json['source']?.toString() ?? 'QUICK',
  );
  final String id;
  final int amountMl;
  final DateTime occurredAt;
  final String source;
}

class HydrationDay {
  const HydrationDay({
    required this.date,
    required this.status,
    required this.consumedMl,
    required this.targetMl,
    required this.remainingMl,
    required this.progress,
    required this.targetSource,
    required this.settings,
    required this.entries,
  });
  factory HydrationDay.fromJson(Map<String, dynamic> json) {
    final settings = HydrationSettings.fromJson(_map(json['settings']));
    final entries =
        (json['entries'] as List? ?? const [])
            .map((e) => HydrationEntry.fromJson(_map(e)))
            .toList(growable: false)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return HydrationDay(
      date: DateTime.parse(json['date'].toString()),
      status: json['status']?.toString() ?? 'ERROR',
      consumedMl: (json['consumedMl'] as num?)?.toInt() ?? 0,
      targetMl:
          (json['targetMl'] as num?)?.toInt() ?? settings.effectiveTargetMl,
      remainingMl: (json['remainingMl'] as num?)?.toInt() ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      targetSource: _source(json['targetSource']),
      settings: settings,
      entries: entries,
    );
  }
  final DateTime date;
  final String status;
  final int consumedMl;
  final int targetMl;
  final int remainingMl;
  final double progress;
  final HydrationTargetSource targetSource;
  final HydrationSettings settings;
  final List<HydrationEntry> entries;
  HydrationDay optimistic(int amount) => HydrationDay(
    date: date,
    status: 'READY',
    consumedMl: consumedMl + amount,
    targetMl: targetMl,
    remainingMl: (targetMl - consumedMl - amount).clamp(0, targetMl),
    progress: targetMl == 0 ? 0 : (consumedMl + amount) / targetMl,
    targetSource: targetSource,
    settings: settings,
    entries: entries,
  );
}
