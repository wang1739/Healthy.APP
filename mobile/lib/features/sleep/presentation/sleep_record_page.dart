import 'package:flutter/material.dart';
import 'package:healthy/features/sleep/application/sleep_controller.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';

class SleepRecordPage extends StatefulWidget {
  const SleepRecordPage({
    required this.controller,
    required this.selectedDate,
    this.initialRecord,
    this.initialType = SleepRecordType.night,
    this.now,
    super.key,
  });
  final SleepController controller;
  final DateTime selectedDate;
  final SleepRecord? initialRecord;
  final SleepRecordType initialType;
  final DateTime Function()? now;
  @override
  State<SleepRecordPage> createState() => _SleepRecordPageState();
}

class _SleepRecordPageState extends State<SleepRecordPage> {
  late SleepRecordType _type;
  late DateTime _startedAt;
  late DateTime _endedAt;
  int? _quality;
  final _tags = <String>{};
  final _note = TextEditingController();
  bool _showNote = false;
  String? _error;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    _type = record?.type ?? widget.initialType;
    _endedAt =
        record?.endedAt.toLocal() ??
        DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          _now.hour,
          _now.minute,
        );
    _startedAt =
        record?.startedAt.toLocal() ??
        _endedAt.subtract(
          Duration(minutes: _type == SleepRecordType.night ? 480 : 30),
        );
    _quality = record?.qualityScore;
    _tags.addAll(record?.tags ?? const []);
    _note.text = record?.note ?? '';
    _showNote = _note.text.isNotEmpty;
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _note.dispose();
    super.dispose();
  }

  int get _duration => _endedAt.difference(_startedAt).inMinutes;
  String _durationText(int minutes) =>
      minutes < 60 ? '$minutes 分钟' : '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialRecord == null ? '记录睡眠' : '编辑睡眠'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<SleepRecordType>(
              segments: const [
                ButtonSegment(
                  value: SleepRecordType.night,
                  label: Text('夜间睡眠'),
                ),
                ButtonSegment(value: SleepRecordType.nap, label: Text('午睡/小睡')),
              ],
              selected: {_type},
              onSelectionChanged: (value) => _changeType(value.single),
              style: ButtonStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _timeTile('入睡时间', _startedAt, () => _pickTime(true)),
            _timeTile('醒来时间', _endedAt, () => _pickTime(false)),
            const SizedBox(height: 8),
            Text(
              '自动计算时长：${_durationText(_duration)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            const Text(
              '睡眠质量（可选）',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var score = 1; score <= 5; score++)
                  ChoiceChip(
                    label: Text(sleepQualityLabel(score)),
                    selected: _quality == score,
                    onSelected: (selected) =>
                        setState(() => _quality = selected ? score : null),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              '影响因素（可多选）',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in sleepTagLabels.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _tags.contains(entry.key),
                    onSelected: (selected) => setState(
                      () => selected
                          ? _tags.add(entry.key)
                          : _tags.remove(entry.key),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_showNote)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showNote = true),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('添加备注'),
                ),
              )
            else
              TextField(
                key: const Key('sleep-note'),
                controller: _note,
                maxLength: 500,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '备注（最多 500 字）'),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (state.saveError != null)
              Text(
                state.saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          key: const Key('sleep-save'),
          onPressed: state.saving ? null : _save,
          child: Text(state.saving ? '保存中…' : '保存睡眠记录'),
        ),
      ),
    );
  }

  Widget _timeTile(
    String label,
    DateTime value,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      '${value.year}年${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
    ),
    trailing: const Icon(Icons.edit_calendar_outlined),
    onTap: onTap,
  );

  void _changeType(SleepRecordType type) {
    setState(() {
      _type = type;
      if (widget.initialRecord == null) {
        _startedAt = _endedAt.subtract(
          Duration(minutes: type == SleepRecordType.night ? 480 : 30),
        );
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _startedAt : _endedAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: _now.add(const Duration(minutes: 5)),
      helpText: start ? '选择入睡日期' : '选择醒来日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? '选择入睡时间' : '选择醒来时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (time == null) return;
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _startedAt = value;
      } else {
        _endedAt = value;
      }
    });
  }

  Future<void> _save() async {
    final duration = _duration;
    final min = _type == SleepRecordType.night ? 30 : 5;
    final max = _type == SleepRecordType.night ? 960 : 240;
    final error = !_startedAt.isBefore(_endedAt)
        ? '入睡时间必须早于醒来时间'
        : _endedAt.isAfter(_now.add(const Duration(minutes: 5)))
        ? '醒来时间不能晚于现在 5 分钟以上'
        : duration < min || duration > max
        ? _type == SleepRecordType.night
              ? '夜间睡眠应为 30 分钟至 16 小时'
              : '小睡应为 5 分钟至 4 小时'
        : _note.text.trim().length > 500
        ? '备注不能超过 500 字'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);
    final payload = <String, dynamic>{
      'recordType': _type.wireName,
      'startedAt': _startedAt.toUtc().toIso8601String(),
      'endedAt': _endedAt.toUtc().toIso8601String(),
      if (_quality != null) 'qualityScore': _quality,
      'tags': _tags.toList(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };
    await widget.controller.save(payload, recordId: widget.initialRecord?.id);
    if (mounted && widget.controller.state.saveError == null) {
      Navigator.pop(context, true);
    }
  }
}
