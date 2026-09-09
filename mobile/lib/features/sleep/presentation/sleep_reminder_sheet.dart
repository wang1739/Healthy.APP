import 'package:flutter/material.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';

class SleepReminderSheet extends StatefulWidget {
  const SleepReminderSheet({
    required this.accountKey,
    required this.scheduler,
    super.key,
  });
  final String accountKey;
  final SleepReminderScheduler scheduler;
  @override
  State<SleepReminderSheet> createState() => _SleepReminderSheetState();
}

class _SleepReminderSheetState extends State<SleepReminderSheet> {
  SleepReminderSettings? _settings;
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    widget.scheduler.load(widget.accountKey).then((value) {
      if (mounted) setState(() => _settings = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: settings == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('睡前提醒', style: Theme.of(context).textTheme.titleLarge),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开启睡前提醒'),
                    subtitle: const Text('提醒仅保存在当前设备'),
                    value: settings.enabled,
                    onChanged: (value) => setState(
                      () => _settings = settings.copyWith(enabled: value),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('提醒时间'),
                    trailing: Text(
                      '${settings.hour.toString().padLeft(2, '0')}:${settings.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: _pickTime,
                  ),
                  const Text(
                    '重复星期',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(
                            const ['一', '二', '三', '四', '五', '六', '日'][day - 1],
                          ),
                          selected: settings.weekdays.contains(day),
                          onSelected: (selected) => setState(() {
                            final days = {...settings.weekdays};
                            selected ? days.add(day) : days.remove(day);
                            _settings = settings.copyWith(weekdays: days);
                          }),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                    ],
                  ),
                  if (settings.permissionDenied) ...[
                    const SizedBox(height: 8),
                    const Text('通知权限未开启，睡眠记录仍可正常使用。'),
                    TextButton(
                      onPressed: widget.scheduler.openNotificationSettings,
                      child: const Text('前往系统设置'),
                    ),
                  ],
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存提醒设置'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final value = _settings!;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
      helpText: '选择提醒时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (time != null) {
      setState(
        () => _settings = value.copyWith(hour: time.hour, minute: time.minute),
      );
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.scheduler.save(widget.accountKey, _settings!);
      if (!mounted) return;
      if (saved.permissionDenied) {
        setState(() {
          _settings = saved;
          _saving = false;
        });
        return;
      }
      Navigator.pop(context);
    } on FormatException catch (error) {
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }
}
