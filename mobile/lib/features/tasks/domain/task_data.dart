enum TaskSource { plan, user, unknown }

extension TaskSourceText on TaskSource {
  String get wireName => name.toUpperCase();
  String get label => switch (this) {
    TaskSource.plan => '来自健康计划',
    TaskSource.user => '我创建的',
    TaskSource.unknown => '来源未知',
  };
}

enum TaskCategory { health, work, life, study, other }

extension TaskCategoryText on TaskCategory {
  String get wireName => name.toUpperCase();
  String get label => switch (this) {
    TaskCategory.health => '健康',
    TaskCategory.work => '工作',
    TaskCategory.life => '生活',
    TaskCategory.study => '学习',
    TaskCategory.other => '其他',
  };
}

enum TaskPriority { normal, important, urgent }

extension TaskPriorityText on TaskPriority {
  String get wireName => name.toUpperCase();
  String get label => switch (this) {
    TaskPriority.normal => '普通',
    TaskPriority.important => '重要',
    TaskPriority.urgent => '紧急',
  };
}

enum TaskStatus { pending, completed, skipped, unknown }

enum TaskCompletionSource { user, autoHealthData, unknown }

enum TaskRecurrence { none, daily, weekdays, weekends, weeklyDays }

extension TaskRecurrenceText on TaskRecurrence {
  String get wireName => switch (this) {
    TaskRecurrence.none => 'NONE',
    TaskRecurrence.daily => 'DAILY',
    TaskRecurrence.weekdays => 'WEEKDAYS',
    TaskRecurrence.weekends => 'WEEKENDS',
    TaskRecurrence.weeklyDays => 'WEEKLY_DAYS',
  };

  String get label => switch (this) {
    TaskRecurrence.none => '不重复',
    TaskRecurrence.daily => '每天',
    TaskRecurrence.weekdays => '工作日',
    TaskRecurrence.weekends => '周末',
    TaskRecurrence.weeklyDays => '每周指定日期',
  };
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
int _int(Object? value, [int fallback = 0]) => switch (value) {
  num number => number.toInt(),
  String text => int.tryParse(text) ?? fallback,
  _ => fallback,
};
DateTime _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
DateTime? _nullableDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

TaskCategory _category(Object? value) => switch (value) {
  'HEALTH' => TaskCategory.health,
  'WORK' => TaskCategory.work,
  'LIFE' => TaskCategory.life,
  'STUDY' => TaskCategory.study,
  _ => TaskCategory.other,
};
TaskPriority _priority(Object? value) => switch (value) {
  'IMPORTANT' => TaskPriority.important,
  'URGENT' => TaskPriority.urgent,
  _ => TaskPriority.normal,
};
TaskSource _source(Object? value) => switch (value) {
  'PLAN' => TaskSource.plan,
  'USER' => TaskSource.user,
  _ => TaskSource.unknown,
};
TaskStatus _status(Object? value) => switch (value) {
  'PENDING' => TaskStatus.pending,
  'COMPLETED' => TaskStatus.completed,
  'SKIPPED' => TaskStatus.skipped,
  _ => TaskStatus.unknown,
};
TaskCompletionSource _completionSource(Object? value) => switch (value) {
  'USER' => TaskCompletionSource.user,
  'AUTO_HEALTH_DATA' => TaskCompletionSource.autoHealthData,
  _ => TaskCompletionSource.unknown,
};
TaskRecurrence _recurrence(Object? value) => switch (value) {
  'DAILY' => TaskRecurrence.daily,
  'WEEKDAYS' => TaskRecurrence.weekdays,
  'WEEKENDS' => TaskRecurrence.weekends,
  'WEEKLY_DAYS' => TaskRecurrence.weeklyDays,
  _ => TaskRecurrence.none,
};

class TaskTemplate {
  const TaskTemplate({
    required this.id,
    required this.version,
    required this.recurrence,
    required this.weekdays,
  });

  factory TaskTemplate.fromJson(Map<String, dynamic> json) => TaskTemplate(
    id: json['id']?.toString() ?? '',
    version: _int(json['version']),
    recurrence: _recurrence(json['recurrenceType']),
    weekdays: (json['weekdays'] as List? ?? const [])
        .map(_int)
        .where((day) => day >= 1 && day <= 7)
        .toSet(),
  );

  final String id;
  final int version;
  final TaskRecurrence recurrence;
  final Set<int> weekdays;
}

class TaskInstance {
  const TaskInstance({
    required this.id,
    required this.title,
    required this.source,
    required this.category,
    required this.priority,
    required this.status,
    required this.currentLocalDate,
    required this.allDay,
    required this.recurrence,
    required this.weekdays,
    this.templateId,
    this.templateVersion = 0,
    this.note,
    this.originalLocalDate,
    this.currentDueAt,
    this.reminderOffsetMinutes,
    this.completionSource = TaskCompletionSource.unknown,
    this.completionReason,
    this.postponeCount = 0,
    this.overdue = false,
    this.hasPlanUpdate = false,
  });

  factory TaskInstance.fromJson(Map<String, dynamic> json) => TaskInstance(
    id: json['id']?.toString() ?? '',
    templateId: json['templateId']?.toString(),
    templateVersion: _int(json['templateVersion'] ?? json['version']),
    title: json['title']?.toString() ?? '',
    note: json['note']?.toString(),
    source: _source(json['source']),
    category: _category(json['category']),
    priority: _priority(json['priority']),
    status: _status(json['status']),
    completionSource: _completionSource(json['completionSource']),
    completionReason:
        (json['completionReason'] ?? json['healthCompletionReason'])
            ?.toString(),
    originalLocalDate: json['originalLocalDate'] == null
        ? null
        : _date(json['originalLocalDate']),
    currentLocalDate: _date(
      json['currentLocalDate'] ?? json['date'] ?? json['originalLocalDate'],
    ),
    currentDueAt: _nullableDate(json['currentDueAt'] ?? json['dueAt']),
    allDay: json['allDay'] == true,
    reminderOffsetMinutes: json['reminderOffsetMinutes'] == null
        ? null
        : _int(json['reminderOffsetMinutes']),
    recurrence: _recurrence(json['recurrenceType']),
    weekdays: (json['weekdays'] as List? ?? const [])
        .map(_int)
        .where((day) => day >= 1 && day <= 7)
        .toSet(),
    postponeCount: _int(json['postponeCount']),
    overdue: json['overdue'] == true,
    hasPlanUpdate: json['hasPlanUpdate'] == true,
  );

  final String id;
  final String? templateId;
  final int templateVersion;
  final String title;
  final String? note;
  final TaskSource source;
  final TaskCategory category;
  final TaskPriority priority;
  final TaskStatus status;
  final TaskCompletionSource completionSource;
  final String? completionReason;
  final DateTime? originalLocalDate;
  final DateTime currentLocalDate;
  final DateTime? currentDueAt;
  final bool allDay;
  final int? reminderOffsetMinutes;
  final TaskRecurrence recurrence;
  final Set<int> weekdays;
  final int postponeCount;
  final bool overdue;
  final bool hasPlanUpdate;

  bool get completed => status == TaskStatus.completed;
  bool get skipped => status == TaskStatus.skipped;
  bool get pending => status == TaskStatus.pending;

  TaskInstance copyWith({
    TaskStatus? status,
    DateTime? currentLocalDate,
    DateTime? currentDueAt,
    int? postponeCount,
  }) => TaskInstance(
    id: id,
    templateId: templateId,
    templateVersion: templateVersion,
    title: title,
    note: note,
    source: source,
    category: category,
    priority: priority,
    status: status ?? this.status,
    completionSource: completionSource,
    completionReason: completionReason,
    originalLocalDate: originalLocalDate,
    currentLocalDate: currentLocalDate ?? this.currentLocalDate,
    currentDueAt: currentDueAt ?? this.currentDueAt,
    allDay: allDay,
    reminderOffsetMinutes: reminderOffsetMinutes,
    recurrence: recurrence,
    weekdays: weekdays,
    postponeCount: postponeCount ?? this.postponeCount,
    overdue: overdue,
    hasPlanUpdate: hasPlanUpdate,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (templateId != null) 'templateId': templateId,
    'templateVersion': templateVersion,
    'title': title,
    if (note != null) 'note': note,
    'source': source.wireName,
    'category': category.wireName,
    'priority': priority.wireName,
    'status': status.name.toUpperCase(),
    if (completionSource != TaskCompletionSource.unknown)
      'completionSource':
          completionSource == TaskCompletionSource.autoHealthData
          ? 'AUTO_HEALTH_DATA'
          : 'USER',
    if (completionReason != null) 'completionReason': completionReason,
    if (originalLocalDate != null)
      'originalLocalDate': _formatDate(originalLocalDate!),
    'currentLocalDate': _formatDate(currentLocalDate),
    if (currentDueAt != null)
      'currentDueAt': currentDueAt!.toUtc().toIso8601String(),
    'allDay': allDay,
    if (reminderOffsetMinutes != null)
      'reminderOffsetMinutes': reminderOffsetMinutes,
    'recurrenceType': recurrence.wireName,
    'weekdays': weekdays.toList()..sort(),
    'postponeCount': postponeCount,
    'overdue': overdue,
    'hasPlanUpdate': hasPlanUpdate,
  };
}

class TaskDaySummary {
  const TaskDaySummary({
    this.totalCount = 0,
    this.completedCount = 0,
    this.pendingCount = 0,
    this.overdueCount = 0,
    this.nextTaskId,
  });
  factory TaskDaySummary.fromJson(Map<String, dynamic> json) => TaskDaySummary(
    totalCount: _int(json['totalCount']),
    completedCount: _int(json['completedCount']),
    pendingCount: _int(json['pendingCount']),
    overdueCount: _int(json['overdueCount']),
    nextTaskId: (json['nextTaskId'] ?? _map(json['nextTask'])['id'])
        ?.toString(),
  );
  final int totalCount;
  final int completedCount;
  final int pendingCount;
  final int overdueCount;
  final String? nextTaskId;
  Map<String, dynamic> toJson() => {
    'totalCount': totalCount,
    'completedCount': completedCount,
    'pendingCount': pendingCount,
    'overdueCount': overdueCount,
    if (nextTaskId != null) 'nextTaskId': nextTaskId,
  };
}

class TaskDay {
  const TaskDay({
    required this.date,
    required this.status,
    required this.timeline,
    required this.allDay,
    required this.completed,
    required this.skipped,
    required this.summary,
  });
  factory TaskDay.fromJson(Map<String, dynamic> json) {
    List<TaskInstance> tasks(String key) => (json[key] as List? ?? const [])
        .map((value) => TaskInstance.fromJson(_map(value)))
        .toList(growable: false);
    return TaskDay(
      date: _date(json['date']),
      status: json['status']?.toString() ?? 'EMPTY',
      timeline: tasks('timeline'),
      allDay: tasks('allDay'),
      completed: tasks('completed'),
      skipped: tasks('skipped'),
      summary: TaskDaySummary.fromJson(_map(json['summary'])),
    );
  }
  final DateTime date;
  final String status;
  final List<TaskInstance> timeline;
  final List<TaskInstance> allDay;
  final List<TaskInstance> completed;
  final List<TaskInstance> skipped;
  final TaskDaySummary summary;
  List<TaskInstance> get allTasks => [
    ...timeline,
    ...allDay,
    ...completed,
    ...skipped,
  ];
  TaskInstance? byId(String id) {
    for (final task in allTasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  TaskDay replace(TaskInstance updated) {
    List<TaskInstance> map(List<TaskInstance> source) => source
        .map((task) => task.id == updated.id ? updated : task)
        .toList(growable: false);
    final pending = updated.pending;
    final current = allTasks.where((task) => task.id != updated.id).toList();
    current.add(updated);
    return TaskDay(
      date: date,
      status: status,
      timeline: pending && !updated.allDay
          ? [
              ...map(timeline.where((t) => t.id != updated.id).toList()),
              updated,
            ]
          : map(timeline.where((t) => t.id != updated.id).toList()),
      allDay: pending && updated.allDay
          ? [...map(allDay.where((t) => t.id != updated.id).toList()), updated]
          : map(allDay.where((t) => t.id != updated.id).toList()),
      completed: updated.completed
          ? [...completed.where((t) => t.id != updated.id), updated]
          : completed.where((t) => t.id != updated.id).toList(),
      skipped: updated.skipped
          ? [...skipped.where((t) => t.id != updated.id), updated]
          : skipped.where((t) => t.id != updated.id).toList(),
      summary: TaskDaySummary(
        totalCount: current.length,
        completedCount: current.where((task) => task.completed).length,
        pendingCount: current.where((task) => task.pending).length,
        overdueCount: current
            .where((task) => task.pending && task.overdue)
            .length,
        nextTaskId: summary.nextTaskId,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': _formatDate(date),
    'status': status,
    'timeline': timeline.map((task) => task.toJson()).toList(),
    'allDay': allDay.map((task) => task.toJson()).toList(),
    'completed': completed.map((task) => task.toJson()).toList(),
    'skipped': skipped.map((task) => task.toJson()).toList(),
    'summary': summary.toJson(),
  };
}

class TaskCategoryProgress {
  const TaskCategoryProgress({
    required this.category,
    required this.expectedCount,
    required this.completedCount,
  });
  factory TaskCategoryProgress.fromJson(Map<String, dynamic> json) =>
      TaskCategoryProgress(
        category: _category(json['category']),
        expectedCount: _int(json['expectedCount'] ?? json['totalCount']),
        completedCount: _int(json['completedCount']),
      );
  final TaskCategory category;
  final int expectedCount;
  final int completedCount;
}

class TaskWeek {
  const TaskWeek({
    required this.startDate,
    required this.endDate,
    required this.expectedCount,
    required this.completedCount,
    required this.skippedCount,
    required this.postponedCount,
    required this.overdueCount,
    required this.categories,
    this.completionRate,
  });
  factory TaskWeek.fromJson(Map<String, dynamic> json) => TaskWeek(
    startDate: _date(json['startDate']),
    endDate: _date(json['endDate']),
    expectedCount: _int(json['expectedCount'] ?? json['totalCount']),
    completedCount: _int(json['completedCount']),
    skippedCount: _int(json['skippedCount']),
    postponedCount: _int(json['postponedCount']),
    overdueCount: _int(json['overdueCount']),
    completionRate: json['completionRate'] is num
        ? (json['completionRate'] as num).toDouble()
        : null,
    categories:
        (json['categories'] as List? ??
                json['categoryBreakdown'] as List? ??
                const [])
            .map((value) => TaskCategoryProgress.fromJson(_map(value)))
            .toList(growable: false),
  );
  final DateTime startDate;
  final DateTime endDate;
  final int expectedCount;
  final int completedCount;
  final int skippedCount;
  final int postponedCount;
  final int overdueCount;
  final double? completionRate;
  final List<TaskCategoryProgress> categories;
}

class TaskSettings {
  const TaskSettings({
    this.quietEnabled = true,
    this.quietStartTime = '22:30',
    this.quietEndTime = '07:00',
    this.version = 0,
    this.notificationPermissionDenied = false,
  });
  factory TaskSettings.fromJson(Map<String, dynamic> json) => TaskSettings(
    quietEnabled: json['quietEnabled'] != false,
    quietStartTime: json['quietStartTime']?.toString() ?? '22:30',
    quietEndTime: json['quietEndTime']?.toString() ?? '07:00',
    version: _int(json['version']),
    notificationPermissionDenied: json['notificationPermissionDenied'] == true,
  );
  final bool quietEnabled;
  final String quietStartTime;
  final String quietEndTime;
  final int version;
  final bool notificationPermissionDenied;
  int get quietStartMinutes => _timeMinutes(quietStartTime);
  int get quietEndMinutes => _timeMinutes(quietEndTime);
  TaskSettings copyWith({
    bool? quietEnabled,
    String? quietStartTime,
    String? quietEndTime,
    bool? notificationPermissionDenied,
  }) => TaskSettings(
    quietEnabled: quietEnabled ?? this.quietEnabled,
    quietStartTime: quietStartTime ?? this.quietStartTime,
    quietEndTime: quietEndTime ?? this.quietEndTime,
    version: version,
    notificationPermissionDenied:
        notificationPermissionDenied ?? this.notificationPermissionDenied,
  );
  Map<String, dynamic> toJson() => {
    'quietEnabled': quietEnabled,
    'quietStartTime': quietStartTime,
    'quietEndTime': quietEndTime,
    'version': version,
  };
}

class TaskNotification {
  const TaskNotification({
    required this.instanceId,
    required this.title,
    required this.currentLocalDate,
    required this.dueAt,
    required this.reminderOffsetMinutes,
  });
  factory TaskNotification.fromJson(Map<String, dynamic> json) {
    final dueAt = _date(json['dueAt'] ?? json['currentDueAt']);
    final notifyAt = _nullableDate(json['notifyAt']);
    return TaskNotification(
      instanceId: (json['instanceId'] ?? json['id'])?.toString() ?? '',
      title: json['title']?.toString() ?? '任务提醒',
      currentLocalDate: json['currentLocalDate'] == null
          ? DateTime(
              dueAt.toLocal().year,
              dueAt.toLocal().month,
              dueAt.toLocal().day,
            )
          : _date(json['currentLocalDate']),
      dueAt: notifyAt ?? dueAt,
      reminderOffsetMinutes: notifyAt == null
          ? _int(json['reminderOffsetMinutes'])
          : 0,
    );
  }
  final String instanceId;
  final String title;
  final DateTime currentLocalDate;
  final DateTime dueAt;
  final int reminderOffsetMinutes;
}

class TaskMutationResult {
  const TaskMutationResult({required this.instance, this.day});
  factory TaskMutationResult.fromJson(Map<String, dynamic> json) {
    final instances = json['instances'] as List?;
    final raw =
        json['instance'] ??
        json['task'] ??
        (instances?.isNotEmpty == true ? instances!.first : null) ??
        (json.containsKey('id') ? json : null);
    return TaskMutationResult(
      instance: TaskInstance.fromJson(_map(raw)),
      day: json['day'] is Map ? TaskDay.fromJson(_map(json['day'])) : null,
    );
  }
  final TaskInstance instance;
  final TaskDay? day;
}

class TaskDraft {
  const TaskDraft({
    required this.title,
    this.note,
    this.category = TaskCategory.life,
    this.priority = TaskPriority.normal,
    this.allDay = true,
    this.localDate,
    this.localTime,
    this.recurrence = TaskRecurrence.none,
    this.weekdays = const {},
    this.reminderOffsetMinutes,
  });
  final String title;
  final String? note;
  final TaskCategory category;
  final TaskPriority priority;
  final bool allDay;
  final DateTime? localDate;
  final String? localTime;
  final TaskRecurrence recurrence;
  final Set<int> weekdays;
  final int? reminderOffsetMinutes;
  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    if (note?.trim().isNotEmpty == true) 'note': note!.trim(),
    'category': category.wireName,
    'priority': priority.wireName,
    'allDay': allDay,
    if (localDate != null) 'date': _formatDate(localDate!),
    if (!allDay && localTime != null) 'localTime': localTime,
    'recurrenceType': recurrence.wireName,
    if (recurrence == TaskRecurrence.weeklyDays)
      'weekdaysMask': weekdays.fold<int>(
        0,
        (mask, day) => day >= 1 && day <= 7 ? mask | (1 << (day - 1)) : mask,
      ),
    if (!allDay && reminderOffsetMinutes != null)
      'reminderOffsetMinutes': reminderOffsetMinutes,
  };
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
int _timeMinutes(String value) {
  final parts = value.split(':');
  return parts.length == 2 ? (_int(parts[0]) * 60 + _int(parts[1])) : 0;
}
