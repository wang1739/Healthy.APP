import 'package:flutter/material.dart';
import 'package:healthy/features/tasks/application/task_controller.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    required this.controller,
    required this.accountKey,
    required this.selectedDate,
    required this.scheduler,
    this.initialTask,
    super.key,
  });
  final TaskController controller;
  final String accountKey;
  final DateTime selectedDate;
  final TaskNotificationScheduler scheduler;
  final TaskInstance? initialTask;
  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  String? _validation;
  late DateTime _date;
  late TaskCategory _category;
  late TaskPriority _priority;
  late bool _allDay;
  late TimeOfDay _time;
  late TaskRecurrence _recurrence;
  late Set<int> _weekdays;
  int? _reminder;

  @override
  void initState() {
    super.initState();
    final task = widget.initialTask;
    _title.text = task?.title ?? '';
    _note.text = task?.note ?? '';
    _date = task?.currentLocalDate ?? widget.selectedDate;
    _category = task?.category ?? TaskCategory.life;
    _priority = task?.priority ?? TaskPriority.normal;
    _allDay = task?.allDay ?? true;
    final due = task?.currentDueAt?.toLocal();
    _time = due == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay.fromDateTime(due);
    _recurrence = task?.recurrence ?? TaskRecurrence.none;
    _weekdays = {...?task?.weekdays};
    _reminder = task?.reminderOffsetMinutes;
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.controller.state.saving;
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialTask == null ? '新增任务' : '编辑任务')),
      body: SafeArea(
        bottom: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              key: const Key('task-title'),
              controller: _title,
              maxLength: 80,
              decoration: _decoration('任务名称', error: _validation),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('添加备注'),
              children: [
                TextField(
                  controller: _note,
                  maxLength: 500,
                  maxLines: 4,
                  decoration: _decoration('备注（可选）'),
                ),
              ],
            ),
            _dropdown<TaskCategory>(
              '分类',
              _category,
              TaskCategory.values,
              (value) => setState(() => _category = value!),
              (value) => value.label,
            ),
            _dropdown<TaskPriority>(
              '优先级',
              _priority,
              TaskPriority.values,
              (value) => setState(() => _priority = value!),
              (value) => value.label,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('全天任务'),
              value: _allDay,
              onChanged: (value) => setState(() {
                _allDay = value;
                if (value) _reminder = null;
              }),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('日期'),
              trailing: Text('${_date.year}年${_date.month}月${_date.day}日'),
              onTap: _pickDate,
            ),
            if (!_allDay)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('时间'),
                trailing: Text(_time.format(context)),
                onTap: _pickTime,
              ),
            _dropdown<TaskRecurrence>(
              '重复',
              _recurrence,
              TaskRecurrence.values,
              (value) => setState(() => _recurrence = value!),
              (value) => value.label,
            ),
            if (_recurrence == TaskRecurrence.weeklyDays) ...[
              const Text('重复星期', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(
                spacing: 6,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(
                        '周${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
                      ),
                      selected: _weekdays.contains(day),
                      onSelected: (selected) => setState(() {
                        selected ? _weekdays.add(day) : _weekdays.remove(day);
                      }),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                ],
              ),
            ],
            _dropdown<int?>(
              '提醒',
              _reminder,
              const [null, 0, 5, 15, 30, 60],
              _allDay ? null : (value) => setState(() => _reminder = value),
              (value) => value == null
                  ? '不提醒'
                  : value == 0
                  ? '准时提醒'
                  : '提前 $value 分钟',
            ),
            if (widget.controller.state.saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.controller.state.saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          key: const Key('task-editor-save'),
          onPressed: saving ? null : _save,
          child: Text(saving ? '保存中…' : '保存任务'),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? error}) => InputDecoration(
    labelText: label,
    errorText: error,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T?>? changed,
    String Function(T) text,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      hint: value == null ? Text(text(value)) : null,
      decoration: _decoration(label),
      borderRadius: BorderRadius.circular(6),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(text(item))))
          .toList(),
      onChanged: changed,
    ),
  );

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择任务日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: '选择任务时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (time != null) setState(() => _time = time);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final error = title.isEmpty
        ? '请输入任务名称'
        : title.length > 80
        ? '任务名称不能超过 80 个字符'
        : _note.text.length > 500
        ? '备注不能超过 500 个字符'
        : _recurrence == TaskRecurrence.weeklyDays && _weekdays.isEmpty
        ? '请至少选择一天'
        : null;
    if (error != null) {
      setState(() => _validation = error);
      return;
    }
    setState(() => _validation = null);
    TaskEditScope scope = TaskEditScope.instance;
    final task = widget.initialTask;
    if (task != null && task.recurrence != TaskRecurrence.none) {
      final selected = await showDialog<TaskEditScope>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修改重复任务'),
          content: const Text('请选择修改范围'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, TaskEditScope.instance),
              child: const Text('仅修改今天'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, TaskEditScope.template),
              child: const Text('之后都按此安排'),
            ),
          ],
        ),
      );
      if (selected == null) return;
      scope = selected;
    }
    final allowed = await widget.scheduler.ensurePermission(
      widget.accountKey,
      enabling: _reminder != null,
    );
    final draft = TaskDraft(
      title: title,
      note: _note.text,
      category: _category,
      priority: _priority,
      allDay: _allDay,
      localDate: _date,
      localTime: _allDay
          ? null
          : '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      recurrence: _recurrence,
      weekdays: _weekdays,
      reminderOffsetMinutes: _reminder,
    ).toJson();
    if (task != null) draft['version'] = task.templateVersion;
    await widget.controller.save(
      draft,
      instanceId: task?.id,
      templateId: task?.templateId,
      scope: scope,
    );
    if (!mounted || widget.controller.state.saveError != null) return;
    if (!allowed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('通知权限未开启，任务已保存，可在系统设置中开启')));
    }
    if (Navigator.canPop(context)) Navigator.pop(context, true);
  }
}
