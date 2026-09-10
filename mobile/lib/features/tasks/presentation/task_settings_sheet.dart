import 'package:flutter/material.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';

class TaskSettingsSheet extends StatefulWidget {
  const TaskSettingsSheet({
    required this.api,
    required this.accountKey,
    required this.scheduler,
    super.key,
  });
  final ApiClient api;
  final String accountKey;
  final TaskNotificationScheduler scheduler;
  @override
  State<TaskSettingsSheet> createState() => _TaskSettingsSheetState();
}

class _TaskSettingsSheetState extends State<TaskSettingsSheet> {
  TaskSettings? _settings;
  bool _denied = false;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    Future.wait<Object>([
          widget.api.getTaskSettings(),
          widget.scheduler.permissionDenied(widget.accountKey),
        ])
        .then((values) {
          if (mounted) {
            setState(() {
              _settings = values[0] as TaskSettings;
              _denied = values[1] as bool;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _error = '勿扰设置加载失败');
        });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: settings == null
            ? Text(_error ?? '正在加载勿扰设置…')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('任务勿扰设置', style: Theme.of(context).textTheme.titleLarge),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开启勿扰'),
                    value: settings.quietEnabled,
                    onChanged: (value) => setState(
                      () => _settings = settings.copyWith(quietEnabled: value),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始时间'),
                    trailing: Text(settings.quietStartTime),
                    onTap: () => _pick(true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('结束时间'),
                    trailing: Text(settings.quietEndTime),
                    onTap: () => _pick(false),
                  ),
                  const Text('跨午夜时段会自动识别；勿扰期间的提醒不会补发。'),
                  if (_denied) ...[
                    const SizedBox(height: 8),
                    const Text('通知权限未开启，不影响任务保存和使用。'),
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
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存勿扰设置'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _pick(bool start) async {
    final settings = _settings!;
    final raw = (start ? settings.quietStartTime : settings.quietEndTime).split(
      ':',
    );
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(raw[0]),
        minute: int.parse(raw[1]),
      ),
      helpText: start ? '选择勿扰开始时间' : '选择勿扰结束时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (result == null) return;
    final value =
        '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
    setState(() {
      _settings = start
          ? settings.copyWith(quietStartTime: value)
          : settings.copyWith(quietEndTime: value);
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateTaskSettings(_settings!.toJson());
      await widget.scheduler.sync(widget.accountKey);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiClient.errorMessage(error);
        });
      }
    }
  }
}
