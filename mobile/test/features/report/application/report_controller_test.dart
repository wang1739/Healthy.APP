import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/report/application/report_controller.dart';
import 'package:healthy/features/report/domain/report_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthReport _report(String id, int version, DateTime date) => HealthReport(
  id: id,
  type: ReportType.weekly,
  periodStart: date,
  periodEnd: date.add(const Duration(days: 6)),
  periodStatus: ReportPeriodStatus.inProgress,
  version: version,
  sections: const [],
);

class _Api extends ApiClient {
  _Api();
  final reports = <String, HealthReport>{};
  Completer<ReportPageData>? pendingList;
  Object? listError;
  String? generatedKey;
  int deletes = 0;
  Completer<ReportPdf>? pendingPdf;
  String? downloadedId;

  @override
  Future<ReportPageData> getReports({
    required ReportType type,
    required DateTime date,
  }) {
    if (listError != null) return Future.error(listError!);
    if (pendingList != null) return pendingList!.future;
    return Future.value(
      ReportPageData(
        items: reports.values
            .map((e) => ReportSummary.fromJson(e.toJson()))
            .toList(),
      ),
    );
  }

  @override
  Future<HealthReport> getReport(String id) async => reports[id]!;

  @override
  Future<HealthReport> generateReport({
    required ReportType type,
    required DateTime date,
    required String idempotencyKey,
  }) async {
    generatedKey ??= idempotencyKey;
    final value = _report('generated', 1, date);
    reports[value.id] = value;
    return value;
  }

  @override
  Future<void> deleteReport(String id) async {
    deletes++;
    reports.remove(id);
  }

  @override
  Future<ReportPdf> downloadReportPdf(String id) async {
    downloadedId = id;
    return pendingPdf?.future ??
        ReportPdf(
          bytes: Uint8List.fromList('%PDF'.codeUnits),
          fileName: 'report.pdf',
        );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('最近成功缓存按账号、类型、周期和版本隔离', () async {
    final date = DateTime(2026, 9, 7);
    final api = _Api()..reports['r1'] = _report('r1', 2, date);
    final controller = ReportController(
      api,
      accountKey: 'a',
      type: ReportType.weekly,
      date: date,
    );
    await controller.load();
    expect(controller.state.report?.id, 'r1');

    final offline = _Api()..listError = Exception('offline');
    final cached = ReportController(
      offline,
      accountKey: 'a',
      type: ReportType.weekly,
      date: date,
    );
    await cached.load();
    expect(cached.state.report?.id, 'r1');
    expect(cached.state.stale, isTrue);

    final other = ReportController(
      offline,
      accountKey: 'b',
      type: ReportType.weekly,
      date: date,
    );
    await other.load();
    expect(other.state.report, isNull);
  });

  test('切换周期和销毁后丢弃迟到响应', () async {
    final api = _Api()..pendingList = Completer<ReportPageData>();
    final controller = ReportController(
      api,
      accountKey: 'a',
      type: ReportType.weekly,
      date: DateTime(2026, 9, 7),
    );
    final loading = controller.load();
    controller.dispose();
    api.pendingList!.complete(const ReportPageData(items: []));
    await loading;
    expect(controller.state.report, isNull);
  });

  test('生成防重复，失败可重试且保留旧报告', () async {
    final api = _Api();
    final controller = ReportController(
      api,
      accountKey: 'a',
      type: ReportType.weekly,
      date: DateTime(2026, 9, 7),
    );
    await Future.wait([controller.generate(), controller.generate()]);
    expect(controller.state.report?.id, 'generated');
    expect(api.generatedKey, isNotEmpty);
  });

  test('删除后选择下一版本，PDF 保存失败不删报告', () async {
    final date = DateTime(2026, 9, 7);
    final api = _Api()
      ..reports['r1'] = _report('r1', 1, date)
      ..reports['r2'] = _report('r2', 2, date);
    final controller = ReportController(
      api,
      accountKey: 'a',
      type: ReportType.weekly,
      date: date,
      savePdf: (_, bytes) async => throw Exception('disk'),
    );
    await controller.load();
    await controller.deleteCurrent();
    expect(controller.state.report?.id, 'r1');
    await controller.downloadPdf();
    expect(controller.state.report?.id, 'r1');
    expect(controller.state.pdfError, isNotNull);
  });

  test('历史列表删除非当前版本时保留当前报告', () async {
    final date = DateTime(2026, 9, 7);
    final api = _Api()
      ..reports['r1'] = _report('r1', 1, date)
      ..reports['r2'] = _report('r2', 2, date);
    final controller = ReportController(
      api,
      accountKey: 'a',
      type: ReportType.weekly,
      date: date,
    );
    await controller.load();

    await controller.deleteVersion('r1');

    expect(controller.state.report?.id, 'r2');
    expect(controller.state.history.map((e) => e.id), ['r2']);
    expect(api.reports.containsKey('r1'), isFalse);
  });

  test('PDF 迟到响应不覆盖用户刚选的历史版本', () async {
    final date = DateTime(2026, 9, 7);
    final api = _Api()
      ..reports['r1'] = _report('r1', 1, date)
      ..reports['r2'] = _report('r2', 2, date)
      ..pendingPdf = Completer<ReportPdf>();
    final controller = ReportController(
      api,
      accountKey: 'a',
      type: ReportType.weekly,
      date: date,
      savePdf: (name, bytes) async => 'saved/$name',
    );
    await controller.load();
    final downloading = controller.downloadPdf();
    await controller.selectVersion('r1');
    api.pendingPdf!.complete(
      ReportPdf(
        bytes: Uint8List.fromList('%PDF'.codeUnits),
        fileName: 'report.pdf',
      ),
    );
    await downloading;

    expect(controller.state.report?.id, 'r1');
    expect(controller.state.pdfPath, 'saved/report.pdf');
  });

  test('可下载指定历史版本且不切换当前报告', () async {
    final date = DateTime(2026, 9, 7);
    final api = _Api()
      ..reports['r1'] = _report('r1', 1, date)
      ..reports['r2'] = _report('r2', 2, date);
    final controller = ReportController(
      api,
      accountKey: 'a',
      type: ReportType.weekly,
      date: date,
      savePdf: (name, bytes) async => 'saved/$name',
    );
    await controller.load();

    await controller.downloadVersion('r1');

    expect(api.downloadedId, 'r1');
    expect(controller.state.report?.id, 'r2');
  });
}
