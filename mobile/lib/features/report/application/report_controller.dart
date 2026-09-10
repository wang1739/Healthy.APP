import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/report/domain/report_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SaveReportPdf = Future<String> Function(String name, List<int> bytes);

class ReportState {
  const ReportState({
    this.report,
    this.history = const [],
    this.loading = false,
    this.generating = false,
    this.deleting = false,
    this.downloading = false,
    this.stale = false,
    this.error,
    this.pdfPath,
    this.pdfError,
  });
  final HealthReport? report;
  final List<ReportSummary> history;
  final bool loading;
  final bool generating;
  final bool deleting;
  final bool downloading;
  final bool stale;
  final String? error;
  final String? pdfPath;
  final String? pdfError;
}

class ReportController extends ChangeNotifier {
  ReportController(
    this.api, {
    required this.accountKey,
    required this.type,
    required DateTime date,
    Future<SharedPreferences> Function()? preferences,
    SaveReportPdf? savePdf,
  }) : date = reportPeriodAnchor(type, date),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _savePdf = savePdf ?? _saveToTemporaryDirectory;

  final ApiClient api;
  final String accountKey;
  final ReportType type;
  final DateTime date;
  final Future<SharedPreferences> Function() _preferences;
  final SaveReportPdf _savePdf;
  ReportState state = const ReportState();
  int _request = 0;
  bool _disposed = false;
  Future<void>? _generation;
  String? _generationKey;

  String get _base =>
      'report_${accountKey}_${type.wireName}_${formatLocalDate(date)}';

  Future<void> load({bool force = false}) async {
    final request = ++_request;
    HealthReport? cached;
    try {
      final prefs = await _preferences();
      final version = prefs.getInt('${_base}_latest');
      final raw = version == null
          ? null
          : prefs.getString('${_base}_v$version');
      if (raw != null) cached = HealthReport.fromJson(jsonDecode(raw));
    } catch (_) {
      // Invalid cache never blocks authoritative loading.
    }
    if (!_active(request)) return;
    state = ReportState(
      report: cached ?? state.report,
      history: state.history,
      loading: true,
      stale: cached != null,
    );
    notifyListeners();
    try {
      final page = await api.getReports(type: type, date: date);
      final history = [...page.items]
        ..sort((a, b) => b.version.compareTo(a.version));
      final report = history.isEmpty
          ? null
          : await api.getReport(history.first.id);
      if (!_active(request)) return;
      state = ReportState(report: report, history: history);
      if (report != null) await _cache(report);
    } catch (error) {
      if (!_active(request)) return;
      state = ReportState(
        report: state.report,
        history: state.history,
        stale: state.report != null,
        error: ApiClient.errorMessage(error),
      );
    }
    if (_active(request)) notifyListeners();
  }

  Future<void> selectVersion(String id) async {
    final request = ++_request;
    state = ReportState(
      report: state.report,
      history: state.history,
      loading: true,
    );
    notifyListeners();
    try {
      final report = await api.getReport(id);
      if (!_active(request)) return;
      state = ReportState(report: report, history: state.history);
      await _cache(report);
    } catch (error) {
      if (!_active(request)) return;
      state = ReportState(
        report: state.report,
        history: state.history,
        error: ApiClient.errorMessage(error),
      );
    }
    if (_active(request)) notifyListeners();
  }

  Future<void> generate() {
    if (_generation != null) return _generation!;
    _generationKey ??= _uuid();
    final operation = _generate();
    _generation = operation;
    return operation.whenComplete(() => _generation = null);
  }

  Future<void> _generate() async {
    state = ReportState(
      report: state.report,
      history: state.history,
      generating: true,
      stale: state.stale,
    );
    notifyListeners();
    try {
      final report = await api.generateReport(
        type: type,
        date: date,
        idempotencyKey: _generationKey!,
      );
      if (_disposed) return;
      _generationKey = null;
      state = ReportState(report: report, history: state.history);
      await _cache(report);
      await load(force: true);
    } catch (error) {
      if (_disposed) return;
      state = ReportState(
        report: state.report,
        history: state.history,
        stale: state.stale,
        error: '${ApiClient.errorMessage(error)}，可重试',
      );
      notifyListeners();
    }
  }

  Future<void> deleteCurrent() async {
    final current = state.report;
    if (current == null) return;
    await deleteVersion(current.id);
  }

  Future<void> deleteVersion(String id) async {
    final current = state.report;
    if (state.deleting) return;
    state = ReportState(
      report: current,
      history: state.history,
      deleting: true,
    );
    notifyListeners();
    try {
      await api.deleteReport(id);
      final deleted = state.history.where((e) => e.id == id).firstOrNull;
      final remaining = state.history.where((e) => e.id != id).toList();
      final next = current?.id == id
          ? (remaining.isEmpty ? null : await api.getReport(remaining.first.id))
          : current;
      if (_disposed) return;
      state = ReportState(report: next, history: remaining);
      await _removeCachedVersion(deleted?.version, next);
    } catch (error) {
      if (_disposed) return;
      state = ReportState(
        report: current,
        history: state.history,
        error: ApiClient.errorMessage(error),
      );
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> downloadPdf() async {
    final current = state.report;
    if (current == null) return;
    await downloadVersion(current.id);
  }

  Future<void> downloadVersion(String id) async {
    if (state.downloading) return;
    state = ReportState(
      report: state.report,
      history: state.history,
      downloading: true,
      stale: state.stale,
      error: state.error,
    );
    notifyListeners();
    try {
      final pdf = await api.downloadReportPdf(id);
      final path = await _savePdf(pdf.fileName, pdf.bytes);
      if (_disposed) return;
      state = ReportState(
        report: state.report,
        history: state.history,
        stale: state.stale,
        error: state.error,
        pdfPath: path,
      );
    } catch (error) {
      if (_disposed) return;
      state = ReportState(
        report: state.report,
        history: state.history,
        stale: state.stale,
        error: state.error,
        pdfError: ApiClient.errorMessage(error),
      );
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _cache(HealthReport report) async {
    try {
      final prefs = await _preferences();
      await prefs.setString(
        '${_base}_v${report.version}',
        jsonEncode(report.toJson()),
      );
      await prefs.setInt('${_base}_latest', report.version);
    } catch (_) {
      // Cache is best-effort.
    }
  }

  Future<void> _removeCachedVersion(int? version, HealthReport? latest) async {
    try {
      final prefs = await _preferences();
      if (version != null) await prefs.remove('${_base}_v$version');
      if (latest == null) {
        await prefs.remove('${_base}_latest');
      } else {
        await _cache(latest);
      }
    } catch (_) {
      // Cache is best-effort.
    }
  }

  static Future<void> clearAccountCache(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs
            .getKeys()
            .where((key) => key.startsWith('report_${accountKey}_'))
            .toList()) {
      await prefs.remove(key);
    }
  }

  bool _active(int request) => !_disposed && request == _request;
  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}

DateTime reportPeriodAnchor(ReportType type, DateTime value) {
  final date = DateTime(value.year, value.month, value.day);
  return switch (type) {
    ReportType.weekly => date.subtract(Duration(days: date.weekday - 1)),
    ReportType.monthly => DateTime(date.year, date.month),
    _ => date,
  };
}

Future<String> _saveToTemporaryDirectory(String name, List<int> bytes) async {
  final directory = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}healthy-reports',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ReportProviderKey {
  const ReportProviderKey(this.api, this.accountKey, this.type, this.date);
  final ApiClient api;
  final String accountKey;
  final ReportType type;
  final DateTime date;
  @override
  bool operator ==(Object other) =>
      other is ReportProviderKey &&
      identical(api, other.api) &&
      accountKey == other.accountKey &&
      type == other.type &&
      reportPeriodAnchor(type, date) == reportPeriodAnchor(type, other.date);
  @override
  int get hashCode => Object.hash(
    identityHashCode(api),
    accountKey,
    type,
    reportPeriodAnchor(type, date),
  );
}

final reportControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ReportController, ReportProviderKey>(
      (ref, key) => ReportController(
        key.api,
        accountKey: key.accountKey,
        type: key.type,
        date: key.date,
      ),
    );
