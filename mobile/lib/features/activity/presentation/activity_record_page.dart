import 'package:flutter/material.dart';
import 'package:healthy/features/activity/application/activity_controller.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';

class ActivityRecordPage extends StatefulWidget {
  const ActivityRecordPage({
    required this.controller,
    required this.selectedDate,
    this.initialRecord,
    this.now,
    super.key,
  });

  final ActivityController controller;
  final DateTime selectedDate;
  final ActivityRecord? initialRecord;
  final DateTime Function()? now;

  @override
  State<ActivityRecordPage> createState() => _ActivityRecordPageState();
}

class _ActivityRecordPageState extends State<ActivityRecordPage> {
  final _duration = TextEditingController(text: '30');
  final _calories = TextEditingController();
  ActivityType? _type;
  ActivityIntensity _intensity = ActivityIntensity.medium;
  late DateTime _occurredAt;
  bool _manualCalories = false;
  String? _error;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    _occurredAt =
        record?.occurredAt.toLocal() ??
        DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          _now.hour,
          _now.minute,
        );
    if (record != null) {
      _duration.text = record.durationMinutes.toString();
      _intensity = record.intensity;
      _manualCalories = record.calorieSource == CalorieSource.userOverride;
      if (_manualCalories) _calories.text = record.finalKcal.toString();
    }
    widget.controller.addListener(_controllerChanged);
    Future.microtask(() async {
      final types = await widget.controller.searchTypes('');
      if (!mounted) return;
      setState(() {
        _type = types
            .where((item) => item.id == record?.activityTypeId)
            .firstOrNull;
      });
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _duration.dispose();
    _calories.dispose();
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  int? get _durationValue => int.tryParse(_duration.text.trim());
  int? get _estimate => _type == null || _durationValue == null
      ? null
      : widget.controller.estimateKcal(_type!, _intensity, _durationValue!);

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialRecord == null ? '记录运动' : '编辑运动'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('activity-search'),
              decoration: const InputDecoration(
                labelText: '搜索运动类型',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: widget.controller.searchTypes,
            ),
            const SizedBox(height: 10),
            if (state.types.isEmpty)
              const Text('未找到运动类型')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in state.types)
                    ChoiceChip(
                      label: Text(type.name),
                      selected: _type?.id == type.id,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _createCustom,
                icon: const Icon(Icons.add),
                label: const Text('创建自定义运动'),
              ),
            ),
            const Divider(),
            const Text('运动强度', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<ActivityIntensity>(
              segments: [
                for (final intensity in ActivityIntensity.values)
                  ButtonSegment(
                    value: intensity,
                    label: Text('${intensity.label}强度'),
                  ),
              ],
              selected: {_intensity},
              onSelectionChanged: (value) =>
                  setState(() => _intensity = value.single),
              style: ButtonStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('运动时长', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in const [15, 30, 45, 60])
                  ChoiceChip(
                    label: Text('$minutes 分钟'),
                    selected: _durationValue == minutes,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    onSelected: (_) =>
                        setState(() => _duration.text = '$minutes'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('activity-duration'),
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '手动输入分钟（1–1440）'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('发生时间'),
              subtitle: Text(
                '${_occurredAt.year}年${_occurredAt.month}月${_occurredAt.day}日 '
                '${_occurredAt.hour.toString().padLeft(2, '0')}:'
                '${_occurredAt.minute.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickOccurredAt,
            ),
            const Divider(),
            Text(
              _estimate == null ? '预计消耗：请选择运动类型' : '预计消耗：$_estimate kcal（估算值）',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (!_manualCalories)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _manualCalories = true;
                    if (_estimate != null) _calories.text = '$_estimate';
                  }),
                  child: const Text('修改消耗热量'),
                ),
              )
            else ...[
              TextField(
                key: const Key('activity-calories'),
                controller: _calories,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '消耗热量（0–10000 kcal）',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _manualCalories = false;
                    _calories.clear();
                  }),
                  child: const Text('恢复估算值'),
                ),
              ),
            ],
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
          key: const Key('activity-save'),
          onPressed: state.saving ? null : _save,
          child: Text(state.saving ? '保存中…' : '保存运动记录'),
        ),
      ),
    );
  }

  Future<void> _pickOccurredAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: _now,
      helpText: '选择运动日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
      helpText: '选择运动时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (time == null) return;
    setState(
      () => _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _createCustom() async {
    var name = '';
    ActivityType? reference = widget.controller.state.types
        .where((item) => item.scope == ActivityTypeScope.system)
        .firstOrNull;
    final type = await showDialog<ActivityType>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建自定义运动'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: '运动名称'),
                onChanged: (value) => name = value,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ActivityType>(
                initialValue: reference,
                decoration: const InputDecoration(labelText: '最相似的内置运动'),
                items: [
                  for (final item in widget.controller.state.types.where(
                    (item) => item.scope == ActivityTypeScope.system,
                  ))
                    DropdownMenuItem(value: item, child: Text(item.name)),
                ],
                onChanged: (value) => setDialogState(() => reference = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.trim().isEmpty || reference == null) return;
                final created = await widget.controller.createCustomType(
                  name,
                  reference!.id,
                );
                if (created != null && dialogContext.mounted) {
                  Navigator.pop(dialogContext, created);
                }
              },
              child: const Text('创建并选择'),
            ),
          ],
        ),
      ),
    );
    if (type != null && mounted) setState(() => _type = type);
  }

  Future<void> _save() async {
    final duration = _durationValue;
    final calories = int.tryParse(_calories.text.trim());
    final error = _type == null
        ? '请选择运动类型'
        : duration == null || duration < 1 || duration > 1440
        ? '运动时长应为 1–1440 分钟'
        : _occurredAt.isAfter(_now)
        ? '发生时间不能晚于现在'
        : _manualCalories &&
              (calories == null || calories < 0 || calories > 10000)
        ? '消耗热量应为 0–10000 kcal'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);
    final payload = <String, dynamic>{
      'activityTypeId': _type!.id,
      'intensity': _intensity.wireName,
      'durationMinutes': duration,
      'occurredAt': _occurredAt.toUtc().toIso8601String(),
      if (_manualCalories) 'finalKcal': calories,
    };
    await widget.controller.save(payload, recordId: widget.initialRecord?.id);
    if (mounted && widget.controller.state.saveError == null) {
      Navigator.pop(context, true);
    }
  }
}
