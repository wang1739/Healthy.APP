import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/report/application/report_controller.dart';
import 'package:healthy/features/report/domain/report_data.dart';
import 'package:healthy/features/report/presentation/report_sources_page.dart';

class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({
    required this.api,
    required this.access,
    required this.accountKey,
    required this.onProtectedAction,
    required this.onOpenSource,
    this.now,
    this.initialIntent,
    this.onIntentHandled,
    this.active = true,
    super.key,
  });
  final ApiClient api;
  final UserAccess access;
  final String accountKey;
  final ValueChanged<String> onProtectedAction;
  final ValueChanged<ReportSource> onOpenSource;
  final DateTime Function()? now;
  final String? initialIntent;
  final VoidCallback? onIntentHandled;
  final bool active;
  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  ReportType _type = ReportType.weekly;
  late DateTime _date;
  late ReportProviderKey _key;
  @override
  void initState() {
    super.initState();
    _date = widget.now?.call() ?? DateTime.now();
    _setKey();
    if (widget.access == UserAccess.profileComplete && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final c = ref.read(reportControllerProvider(_key));
        await c.load();
        if (!mounted || widget.initialIntent == null) return;
        if (widget.initialIntent!.contains('生成')) await c.generate();
        widget.onIntentHandled?.call();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active &&
        widget.active &&
        widget.access == UserAccess.profileComplete) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(reportControllerProvider(_key)).load(),
      );
    }
  }

  void _setKey() =>
      _key = ReportProviderKey(widget.api, widget.accountKey, _type, _date);

  @override
  Widget build(BuildContext context) {
    if (widget.access == UserAccess.guest) return _guest();
    if (widget.access == UserAccess.profileIncomplete) return _incomplete();
    final controller = ref.watch(reportControllerProvider(_key));
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('健康报告')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: SliverList.list(
                children: [
                  _periodControls(),
                  if (state.loading && state.report == null)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (state.report == null)
                    _empty(controller, state.error)
                  else
                    ..._report(controller, state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guest() => Scaffold(
    appBar: AppBar(title: const Text('健康报告')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '健康报告示例',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ReportType>(
            segments: const [
              ButtonSegment(value: ReportType.daily, label: Text('日报')),
              ButtonSegment(value: ReportType.weekly, label: Text('周报')),
              ButtonSegment(value: ReportType.monthly, label: Text('月报')),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() => _type = value.first),
          ),
          const SizedBox(height: 12),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '这是${_type.label}示例',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text('饮食、饮水、运动、睡眠、体重与任务分别展示，不生成综合健康分。'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => widget.onProtectedAction('生成健康报告'),
            child: const Text('登录并生成报告'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onProtectedAction('下载健康报告'),
            child: const Text('下载示例报告'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onProtectedAction('查看报告历史'),
            child: const Text('查看历史版本'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onProtectedAction('查看报告依据'),
            child: const Text('查看示例依据'),
          ),
        ],
      ),
    ),
  );
  Widget _incomplete() => Scaffold(
    appBar: AppBar(title: const Text('健康报告')),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment_ind_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                '先完成健康档案',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('完成建档后会自动回到刚才的报告操作。'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => widget.onProtectedAction('生成健康报告'),
                child: const Text('去完善档案'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _periodControls() => Column(
    children: [
      SegmentedButton<ReportType>(
        segments: const [
          ButtonSegment(value: ReportType.daily, label: Text('日报')),
          ButtonSegment(value: ReportType.weekly, label: Text('周报')),
          ButtonSegment(value: ReportType.monthly, label: Text('月报')),
        ],
        selected: {_type},
        onSelectionChanged: (v) => _change(type: v.first),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          IconButton(
            tooltip: '上一周期',
            onPressed: () => _move(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_periodText),
            ),
          ),
          IconButton(
            tooltip: '下一周期',
            onPressed: () => _move(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ],
  );
  String get _periodText => switch (_type) {
    ReportType.daily => '${_date.month}月${_date.day}日',
    ReportType.weekly =>
      '${reportPeriodAnchor(_type, _date).month}月${reportPeriodAnchor(_type, _date).day}日起自然周',
    ReportType.monthly => '${_date.year}年${_date.month}月',
    _ => '选择周期',
  };
  Widget _empty(ReportController c, String? error) => _card(
    Column(
      children: [
        Icon(
          error == null ? Icons.description_outlined : Icons.cloud_off_outlined,
          size: 44,
        ),
        const SizedBox(height: 10),
        Text(error ?? '这个周期还没有报告'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: c.state.generating ? null : c.generate,
          child: Text(error == null ? '生成报告' : '重试'),
        ),
      ],
    ),
  );

  List<Widget> _report(ReportController c, ReportState state) {
    final r = state.report!;
    return [
      if (state.stale) _notice('已显示最近成功报告，数据可能不是最新'),
      if (state.error != null) _notice(state.error!),
      if (r.sourceDataChanged) _notice('数据已更新，可重新生成'),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.conclusion,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (r.periodStatus == ReportPeriodStatus.inProgress)
                  const Chip(label: Text('进行中')),
              ],
            ),
            const SizedBox(height: 10),
            Text('数据截止：${_dateTime(r.dataCutoffAt)}'),
            Text('数据充分栏目：${r.sufficientSectionCount}/6'),
          ],
        ),
      ),
      if (r.keyMetrics.isNotEmpty) ...[
        const _Heading('关键数字'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: r.keyMetrics.take(3).map(_metric).toList(),
        ),
      ],
      if (r.attentionItems.isNotEmpty) ...[
        const _Heading('需要关注'),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: r.attentionItems
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('• $e'),
                  ),
                )
                .toList(),
          ),
        ),
      ],
      const _Heading('六个核心栏目'),
      ...r.sections.map((s) => _section(r, s)),
      if (r.recommendations.isNotEmpty) ...[
        const _Heading('规则建议'),
        ...r.recommendations.map(
          (e) => _card(
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.title),
              subtitle: Text(e.description),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: state.generating ? null : c.generate,
            child: Text(state.generating ? '生成中…' : '重新生成'),
          ),
          OutlinedButton(
            onPressed: state.downloading ? null : () => _download(c),
            child: Text(state.downloading ? '下载中…' : '下载报告'),
          ),
          OutlinedButton(
            onPressed: () => _history(c),
            child: const Text('历史版本'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(r.disclaimer, style: Theme.of(context).textTheme.bodySmall),
      if (state.pdfError != null) Text('下载失败：${state.pdfError}'),
    ];
  }

  Widget _section(HealthReport r, ReportSection s) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(s.sufficiency.label),
          ],
        ),
        Text(s.sufficiencyReason),
        if (s.summary != null) Text(s.summary!),
        if (s.targetComparison != null) Text(s.targetComparison!),
        if (s.previousComparison != null) Text(s.previousComparison!),
        ...s.metrics.map(
          (m) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(m.label),
            trailing: Text('${m.value}${m.unit ?? ''}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.targetComparison != null) Text(m.targetComparison!),
                if (m.previousComparison != null) Text(m.previousComparison!),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportSourcesPage(
                api: widget.api,
                reportId: r.id,
                section: s.code,
                onOpenSource: widget.onOpenSource,
              ),
            ),
          ),
          child: const Text('查看依据'),
        ),
      ],
    ),
  );
  Widget _metric(ReportMetric m) => SizedBox(
    width: 105,
    child: _card(
      Column(
        children: [
          Text(
            '${m.value}${m.unit ?? ''}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Text(m.label),
        ],
      ),
    ),
  );
  Widget _card(Widget child) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  Widget _notice(String text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text),
  );
  Future<void> _download(ReportController c) async {
    await c.downloadPdf();
    if (!mounted) return;
    if (c.state.pdfPath != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('报告已保存到：${c.state.pdfPath}')));
    }
  }

  Future<void> _history(ReportController c) async => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
    ),
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '历史版本',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (c.state.history.isEmpty) const ListTile(title: Text('暂无历史版本')),
          ...c.state.history.map(
            (e) => ListTile(
              title: Text('版本 ${e.version}'),
              subtitle: Text(
                '${_periodStatusText(e.periodStatus)} · ${_dateTime(e.createdAt)}',
              ),
              onTap: () {
                Navigator.pop(sheet);
                c.selectVersion(e.id);
              },
              trailing: PopupMenuButton<String>(
                tooltip: '版本操作',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                onSelected: (action) {
                  if (action == 'view') {
                    Navigator.pop(sheet);
                    c.selectVersion(e.id);
                  } else if (action == 'download') {
                    Navigator.pop(sheet);
                    _downloadVersion(c, e.id);
                  } else {
                    _confirmDelete(c, sheet, e.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'view', child: Text('查看这个版本')),
                  PopupMenuItem(value: 'download', child: Text('下载这个版本')),
                  PopupMenuItem(value: 'delete', child: Text('删除这个版本')),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _confirmDelete(
    ReportController c,
    BuildContext sheet,
    String reportId,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text('删除报告版本'),
        content: const Text('只删除这个报告快照，不影响任何原始健康记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (yes == true) {
      if (sheet.mounted) Navigator.pop(sheet);
      await c.deleteVersion(reportId);
    }
  }

  Future<void> _pickDate() async {
    final v = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: widget.now?.call() ?? DateTime.now(),
    );
    if (v != null) _change(date: v);
  }

  Future<void> _downloadVersion(ReportController c, String id) async {
    await c.downloadVersion(id);
    if (!mounted) return;
    if (c.state.pdfPath != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('报告已保存到：${c.state.pdfPath}')));
    }
  }

  void _move(int n) {
    final next = switch (_type) {
      ReportType.daily => _date.add(Duration(days: n)),
      ReportType.weekly => _date.add(Duration(days: 7 * n)),
      ReportType.monthly => DateTime(_date.year, _date.month + n),
      _ => _date,
    };
    _change(date: next);
  }

  void _change({ReportType? type, DateTime? date}) {
    setState(() {
      _type = type ?? _type;
      _date = date ?? _date;
      _setKey();
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(reportControllerProvider(_key)).load(),
    );
  }
}

String _dateTime(DateTime? v) => v == null
    ? '—'
    : '${v.toLocal().year}-${v.toLocal().month.toString().padLeft(2, '0')}-${v.toLocal().day.toString().padLeft(2, '0')} ${v.toLocal().hour.toString().padLeft(2, '0')}:${v.toLocal().minute.toString().padLeft(2, '0')}';

String _periodStatusText(ReportPeriodStatus status) => switch (status) {
  ReportPeriodStatus.inProgress => '进行中',
  ReportPeriodStatus.complete => '已完成',
  ReportPeriodStatus.unknown => '状态未知',
};

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
    ),
  );
}
