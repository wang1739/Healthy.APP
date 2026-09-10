import 'dart:typed_data';

enum ReportType { daily, weekly, monthly, unknown }

extension ReportTypeText on ReportType {
  String get wireName => switch (this) {
    ReportType.daily => 'DAILY',
    ReportType.weekly => 'WEEKLY',
    ReportType.monthly => 'MONTHLY',
    ReportType.unknown => 'UNKNOWN',
  };
  String get label => switch (this) {
    ReportType.daily => '日报',
    ReportType.weekly => '周报',
    ReportType.monthly => '月报',
    ReportType.unknown => '报告',
  };
}

enum ReportPeriodStatus { inProgress, complete, unknown }

enum ReportSufficiency { sufficient, limited, empty, notApplicable, unknown }

extension ReportSufficiencyText on ReportSufficiency {
  String get label => switch (this) {
    ReportSufficiency.sufficient => '数据充分',
    ReportSufficiency.limited => '数据有限',
    ReportSufficiency.empty => '暂无记录',
    ReportSufficiency.notApplicable => '当前不适用',
    ReportSufficiency.unknown => '数据状态未知',
  };
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
List _list(Object? value) => value is List ? value : const [];
int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
DateTime _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);

ReportType _type(Object? value) => switch (value) {
  'DAILY' => ReportType.daily,
  'WEEKLY' => ReportType.weekly,
  'MONTHLY' => ReportType.monthly,
  _ => ReportType.unknown,
};
ReportPeriodStatus _periodStatus(Object? value) => switch (value) {
  'IN_PROGRESS' => ReportPeriodStatus.inProgress,
  'COMPLETE' => ReportPeriodStatus.complete,
  _ => ReportPeriodStatus.unknown,
};
ReportSufficiency _sufficiency(Object? value) => switch (value) {
  'SUFFICIENT' => ReportSufficiency.sufficient,
  'LIMITED' => ReportSufficiency.limited,
  'EMPTY' => ReportSufficiency.empty,
  'NOT_APPLICABLE' => ReportSufficiency.notApplicable,
  'sufficient' => ReportSufficiency.sufficient,
  'limited' => ReportSufficiency.limited,
  'empty' => ReportSufficiency.empty,
  'notApplicable' => ReportSufficiency.notApplicable,
  _ => ReportSufficiency.unknown,
};

class ReportMetric {
  const ReportMetric({
    required this.code,
    required this.label,
    required this.value,
    this.unit,
    this.targetComparison,
    this.previousComparison,
  });
  factory ReportMetric.fromJson(Map<String, dynamic> json) => ReportMetric(
    code: json['code']?.toString() ?? '',
    label: json['label']?.toString() ?? '指标',
    value: json['value']?.toString() ?? '—',
    unit: json['unit']?.toString(),
    targetComparison: json['targetComparison']?.toString(),
    previousComparison: json['previousComparison']?.toString(),
  );
  final String code;
  final String label;
  final String value;
  final String? unit;
  final String? targetComparison;
  final String? previousComparison;
  Map<String, dynamic> toJson() => {
    'code': code,
    'label': label,
    'value': value,
    if (unit != null) 'unit': unit,
    if (targetComparison != null) 'targetComparison': targetComparison,
    if (previousComparison != null) 'previousComparison': previousComparison,
  };
}

class ReportSection {
  const ReportSection({
    required this.code,
    required this.title,
    required this.sufficiency,
    required this.sufficiencyReason,
    required this.metrics,
    this.summary,
    this.targetComparison,
    this.previousComparison,
  });
  factory ReportSection.fromJson(Map<String, dynamic> json) {
    final rawMetrics = json['metrics'];
    final metrics = rawMetrics is Map
        ? rawMetrics.entries
              .map(
                (entry) => ReportMetric(
                  code: entry.key.toString(),
                  label: _metricLabel(entry.key.toString()),
                  value: entry.value?.toString() ?? '—',
                ),
              )
              .toList(growable: false)
        : _list(rawMetrics)
              .map((e) => ReportMetric.fromJson(_map(e)))
              .toList(growable: false);
    return ReportSection(
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? '报告栏目',
      sufficiency: _sufficiency(json['sufficiency'] ?? json['status']),
      sufficiencyReason:
          (json['sufficiencyReason'] ?? json['reason'])?.toString() ?? '暂无说明',
      metrics: metrics,
      summary: json['summary']?.toString(),
      targetComparison:
          json['targetComparisonText']?.toString() ??
          _comparisonText(json['targetComparison'], '目标'),
      previousComparison:
          json['previousComparisonText']?.toString() ??
          _comparisonText(json['previousComparison'], '上一周期'),
    );
  }
  final String code;
  final String title;
  final ReportSufficiency sufficiency;
  final String sufficiencyReason;
  final List<ReportMetric> metrics;
  final String? summary;
  final String? targetComparison;
  final String? previousComparison;
  Map<String, dynamic> toJson() => {
    'code': code,
    'title': title,
    'sufficiency': sufficiency.name,
    'sufficiencyReason': sufficiencyReason,
    'metrics': metrics.map((e) => e.toJson()).toList(),
    if (summary != null) 'summary': summary,
    if (targetComparison != null) 'targetComparisonText': targetComparison,
    if (previousComparison != null)
      'previousComparisonText': previousComparison,
  };
}

class ReportRecommendation {
  const ReportRecommendation({
    required this.code,
    required this.title,
    required this.description,
  });
  factory ReportRecommendation.fromJson(Map<String, dynamic> json) =>
      ReportRecommendation(
        code: json['code']?.toString() ?? '',
        title: json['title']?.toString() ?? '建议',
        description: json['description']?.toString() ?? '',
      );
  final String code;
  final String title;
  final String description;
  Map<String, dynamic> toJson() => {
    'code': code,
    'title': title,
    'description': description,
  };
}

class HealthReport {
  const HealthReport({
    required this.id,
    required this.type,
    required this.periodStart,
    required this.periodEnd,
    required this.periodStatus,
    required this.version,
    required this.sections,
    this.dataCutoffAt,
    this.conclusion = '这份报告只总结已记录的事实',
    this.sufficientSectionCount = 0,
    this.keyMetrics = const [],
    this.attentionItems = const [],
    this.recommendations = const [],
    this.sourceDataChanged = false,
    this.createdAt,
    this.disclaimer = '本报告仅用于健康记录回顾，不构成医疗诊断或治疗建议。',
  });
  factory HealthReport.fromJson(Map<String, dynamic> input) {
    final nested = _map(input['report'] ?? input['snapshot']);
    final json = nested.isEmpty ? input : {...input, ...nested};
    final advice = _list(json['recommendations'] ?? json['advice']);
    final completeness = _map(json['completeness']);
    return HealthReport(
      id: json['id']?.toString() ?? '',
      type: _type(json['type'] ?? json['reportType']),
      periodStart: _date(json['periodStart']),
      periodEnd: _date(json['periodEnd']),
      periodStatus: _periodStatus(json['periodStatus']),
      version: _int(json['version']),
      dataCutoffAt: json['dataCutoffAt'] == null
          ? null
          : _date(json['dataCutoffAt']),
      conclusion: json['conclusion']?.toString() ?? '这份报告只总结已记录的事实',
      sufficientSectionCount: _int(
        json['sufficientSectionCount'] ?? completeness['sufficientSections'],
      ),
      keyMetrics: _list(json['keyMetrics'])
          .map((e) => ReportMetric.fromJson(_map(e)))
          .toList(growable: false),
      attentionItems:
          (_list(json['attentionItems']).isNotEmpty
                  ? _list(json['attentionItems']).map((e) => e.toString())
                  : advice.map((e) => _map(e)['description']?.toString() ?? ''))
              .where((e) => e.isNotEmpty)
              .take(3)
              .toList(),
      sections: _list(json['sections'])
          .map((e) => ReportSection.fromJson(_map(e)))
          .toList(growable: false),
      recommendations: advice
          .map((e) => ReportRecommendation.fromJson(_map(e)))
          .take(3)
          .toList(),
      sourceDataChanged: json['sourceDataChanged'] == true,
      createdAt: json['createdAt'] == null ? null : _date(json['createdAt']),
      disclaimer:
          json['disclaimer']?.toString() ?? '本报告仅用于健康记录回顾，不构成医疗诊断或治疗建议。',
    );
  }
  final String id;
  final ReportType type;
  final DateTime periodStart;
  final DateTime periodEnd;
  final ReportPeriodStatus periodStatus;
  final int version;
  final DateTime? dataCutoffAt;
  final String conclusion;
  final int sufficientSectionCount;
  final List<ReportMetric> keyMetrics;
  final List<String> attentionItems;
  final List<ReportSection> sections;
  final List<ReportRecommendation> recommendations;
  final bool sourceDataChanged;
  final DateTime? createdAt;
  final String disclaimer;
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.wireName,
    'periodStart': _formatDate(periodStart),
    'periodEnd': _formatDate(periodEnd),
    'periodStatus': periodStatus == ReportPeriodStatus.inProgress
        ? 'IN_PROGRESS'
        : 'COMPLETE',
    'version': version,
    if (dataCutoffAt != null) 'dataCutoffAt': dataCutoffAt!.toIso8601String(),
    'conclusion': conclusion,
    'sufficientSectionCount': sufficientSectionCount,
    'keyMetrics': keyMetrics.map((e) => e.toJson()).toList(),
    'attentionItems': attentionItems,
    'sections': sections.map((e) => e.toJson()).toList(),
    'recommendations': recommendations.map((e) => e.toJson()).toList(),
    'sourceDataChanged': sourceDataChanged,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    'disclaimer': disclaimer,
  };
}

class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.type,
    required this.periodStart,
    required this.periodEnd,
    required this.version,
    required this.periodStatus,
    this.createdAt,
    this.sourceDataChanged = false,
  });
  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
    id: json['id']?.toString() ?? '',
    type: _type(json['type'] ?? json['reportType']),
    periodStart: _date(json['periodStart']),
    periodEnd: _date(json['periodEnd']),
    version: _int(json['version']),
    periodStatus: _periodStatus(json['periodStatus']),
    createdAt: json['createdAt'] == null ? null : _date(json['createdAt']),
    sourceDataChanged: json['sourceDataChanged'] == true,
  );
  final String id;
  final ReportType type;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int version;
  final ReportPeriodStatus periodStatus;
  final DateTime? createdAt;
  final bool sourceDataChanged;
}

class ReportPageData {
  const ReportPageData({
    required this.items,
    this.page = 0,
    this.totalPages = 1,
  });
  factory ReportPageData.fromJson(Object? input) {
    final json = _map(input);
    final values = input is List
        ? input
        : _list(json['items'] ?? json['content']);
    return ReportPageData(
      items: values.map((e) => ReportSummary.fromJson(_map(e))).toList(),
      page: _int(json['page'] ?? json['number']),
      totalPages: _int(json['totalPages']).clamp(1, 1 << 20),
    );
  }
  final List<ReportSummary> items;
  final int page;
  final int totalPages;
}

class ReportSource {
  const ReportSource({
    required this.sourceType,
    required this.sourceId,
    required this.localDate,
    required this.label,
    this.available = true,
  });
  factory ReportSource.fromJson(Map<String, dynamic> json) => ReportSource(
    sourceType: json['sourceType']?.toString() ?? '',
    sourceId: (json['sourceId'] ?? json['resourceId'])?.toString() ?? '',
    localDate: _date(json['sourceLocalDate'] ?? json['localDate']),
    label: (json['label'] ?? json['locationLabel'])?.toString() ?? '原始记录',
    available: json['available'] != false,
  );
  final String sourceType;
  final String sourceId;
  final DateTime localDate;
  final String label;
  final bool available;
  String get displayLabel => available ? label : '原始记录已删除';
}

class ReportPdf {
  const ReportPdf({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _metricLabel(String code) =>
    const {
      'count': '记录数',
      'latestKg': '最新体重',
      'currentKg': '当前体重',
      'targetKg': '目标体重',
      'recordDays': '记录天数',
      'averageCalories': '平均每日热量',
      'averageDailyMl': '平均每日饮水',
      'recordCount': '运动次数',
      'durationMinutes': '运动时长',
      'nightDays': '夜间睡眠天数',
      'averageNightMinutes': '平均夜间睡眠',
      'totalCount': '应执行任务',
      'completedCount': '已完成任务',
      'postponedCount': '延期任务',
      'completionRate': '任务完成率',
    }[code] ??
    '统计指标';

String? _comparisonText(Object? value, String subject) {
  if (value is String && value.isNotEmpty) return value;
  final map = _map(value);
  if (map.isEmpty) return null;
  if (map['status'] != 'AVAILABLE') return map['reason']?.toString();
  return map.containsKey('difference')
      ? '$subject差值 ${map['difference']}'
      : null;
}
