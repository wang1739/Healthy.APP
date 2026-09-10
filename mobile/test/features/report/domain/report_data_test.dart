import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/report/domain/report_data.dart';

Map<String, dynamic> reportJson() => {
  'id': 'r1',
  'type': 'WEEKLY',
  'periodStart': '2026-09-07',
  'periodEnd': '2026-09-13',
  'periodStatus': 'IN_PROGRESS',
  'version': 2,
  'dataCutoffAt': '2026-09-10T02:00:00Z',
  'conclusion': '本周已有 4 个栏目数据充分',
  'sufficientSectionCount': 4,
  'sourceDataChanged': true,
  'keyMetrics': [
    {'label': '饮水达标', 'value': '5', 'unit': '天'},
  ],
  'attentionItems': ['本周睡眠记录较少'],
  'sections': [
    {
      'code': 'WEIGHT_PLAN',
      'title': '体重与计划',
      'sufficiency': 'LIMITED',
      'sufficiencyReason': '只有 1 次测量',
      'metrics': [
        {
          'code': 'LATEST_WEIGHT',
          'label': '最新体重',
          'value': '65.2',
          'unit': 'kg',
          'targetComparison': null,
          'previousComparison': null,
        },
      ],
    },
    for (final item in const [
      ('NUTRITION', '饮食', 'SUFFICIENT'),
      ('HYDRATION', '饮水', 'SUFFICIENT'),
      ('ACTIVITY', '运动', 'EMPTY'),
      ('SLEEP', '睡眠', 'LIMITED'),
      ('TASKS', '每日任务', 'NOT_APPLICABLE'),
    ])
      {
        'code': item.$1,
        'title': item.$2,
        'sufficiency': item.$3,
        'sufficiencyReason': '服务端说明',
        'metrics': <Object>[],
      },
  ],
  'recommendations': [
    {'code': 'KEEP_RECORDING', 'title': '继续记录', 'description': '记录越完整，周期对比越准确'},
  ],
};

void main() {
  test('解析周期、四种充分性、六个栏目与可空对比', () {
    final report = HealthReport.fromJson(reportJson());

    expect(report.type, ReportType.weekly);
    expect(report.periodStatus, ReportPeriodStatus.inProgress);
    expect(report.sections, hasLength(6));
    expect(
      report.sections.map((e) => e.sufficiency).toSet(),
      containsAll([
        ReportSufficiency.sufficient,
        ReportSufficiency.limited,
        ReportSufficiency.empty,
        ReportSufficiency.notApplicable,
      ]),
    );
    expect(report.sections.first.metrics.single.targetComparison, isNull);
    expect(report.sourceDataChanged, isTrue);
  });

  test('未知枚举安全降级，历史和依据不暴露内部 ID', () {
    final summary = ReportSummary.fromJson({
      'id': 'r2',
      'type': 'FUTURE',
      'periodStart': '2026-09-01',
      'periodEnd': '2026-09-30',
      'version': 1,
      'periodStatus': 'OTHER',
      'createdAt': '2026-09-10T00:00:00Z',
    });
    final source = ReportSource.fromJson({
      'sourceType': 'NUTRITION',
      'sourceId': 'internal-1',
      'sourceLocalDate': '2026-09-09',
      'label': '马兰头餐食记录',
      'available': false,
    });

    expect(summary.type, ReportType.unknown);
    expect(summary.periodStatus, ReportPeriodStatus.unknown);
    expect(source.displayLabel, '原始记录已删除');
    expect(source.displayLabel, isNot(contains('internal-1')));
  });

  test('兼容服务端快照、指标字典、充分度和建议字段', () {
    final report = HealthReport.fromJson({
      'id': 'r3',
      'type': 'MONTHLY',
      'periodStart': '2026-09-01',
      'periodEnd': '2026-09-30',
      'periodStatus': 'COMPLETE',
      'version': 1,
      'snapshot': {
        'conclusion': '本周期有 1 个栏目数据充分。',
        'disclaimer': '本报告仅用于健康记录回顾，不构成医疗建议。',
        'completeness': {'sufficientSections': 1, 'totalSections': 6},
        'sections': [
          {
            'code': 'HYDRATION',
            'title': '饮水',
            'sufficiency': 'LIMITED',
            'reason': '记录较少',
            'metrics': {'recordDays': 2, 'averageDailyMl': 1800},
            'targetComparison': {'status': 'AVAILABLE', 'difference': -200},
            'previousComparison': {
              'status': 'UNAVAILABLE',
              'reason': '上一周期数据不足',
            },
          },
        ],
        'advice': [
          {'code': 'DATA_GAP', 'title': '继续记录', 'description': '下次报告会更准确'},
        ],
      },
    });
    final source = ReportSource.fromJson({
      'sourceType': 'NUTRITION',
      'resourceId': 'n1',
      'localDate': '2026-09-10',
      'locationLabel': '午餐记录',
    });
    expect(report.sufficientSectionCount, 1);
    expect(report.sections.single.metrics, hasLength(2));
    expect(report.sections.single.targetComparison, contains('-200'));
    expect(report.recommendations.single.title, '继续记录');
    expect(report.attentionItems.single, '下次报告会更准确');
    expect(report.disclaimer, contains('不构成医疗建议'));
    expect(source.displayLabel, '午餐记录');
  });
}
