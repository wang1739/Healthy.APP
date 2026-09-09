import 'package:flutter/material.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';

class HydrationSettingsSheet extends StatefulWidget {
  const HydrationSettingsSheet({
    required this.settings,
    required this.onSave,
    required this.onAdoptPlan,
    super.key,
  });
  final HydrationSettings settings;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Future<void> Function() onAdoptPlan;
  @override
  State<HydrationSettingsSheet> createState() => _State();
}

class _State extends State<HydrationSettingsSheet> {
  late final target = TextEditingController(
    text:
        '${widget.settings.dailyTargetMl ?? widget.settings.effectiveTargetMl}',
  );
  late final cup = TextEditingController(
    text: '${widget.settings.defaultCupMl}',
  );
  late bool enabled = widget.settings.reminderEnabled;
  late TimeOfDay reminderStart = _parse(widget.settings.reminderStart);
  late TimeOfDay reminderEnd = _parse(widget.settings.reminderEnd);
  late int interval = widget.settings.reminderIntervalMinutes;
  late bool quietEnabled = widget.settings.quietStart != null;
  late TimeOfDay quietStart = _parse(widget.settings.quietStart ?? '22:00');
  late TimeOfDay quietEnd = _parse(widget.settings.quietEnd ?? '07:00');
  String? error;
  static TimeOfDay _parse(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _wire(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  Future<void> _pick(TimeOfDay initial, ValueChanged<TimeOfDay> update) async {
    final result = await showTimePicker(context: context, initialTime: initial);
    if (result != null) setState(() => update(result));
  }

  @override
  void dispose() {
    target.dispose();
    cup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('饮水设置', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: target,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每日目标（ml）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cup,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '默认杯量（ml）'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('提醒'),
            subtitle: const Text('开启时才会请求通知权限；拒绝后仍可记录'),
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _pick(reminderStart, (v) => reminderStart = v),
                child: Text('开始 ${_wire(reminderStart)}'),
              ),
              OutlinedButton(
                onPressed: () => _pick(reminderEnd, (v) => reminderEnd = v),
                child: Text('结束 ${_wire(reminderEnd)}'),
              ),
              DropdownButton<int>(
                value: [30, 60, 90, 120, 180, 240].contains(interval)
                    ? interval
                    : 120,
                items: [30, 60, 90, 120, 180, 240]
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text('每 $v 分钟')),
                    )
                    .toList(),
                onChanged: (v) => setState(() => interval = v ?? interval),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('勿扰时段'),
            value: quietEnabled,
            onChanged: (v) => setState(() => quietEnabled = v),
          ),
          if (quietEnabled)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _pick(quietStart, (v) => quietStart = v),
                  child: Text('勿扰开始 ${_wire(quietStart)}'),
                ),
                OutlinedButton(
                  onPressed: () => _pick(quietEnd, (v) => quietEnd = v),
                  child: Text('勿扰结束 ${_wire(quietEnd)}'),
                ),
              ],
            ),
          if (widget.settings.planTargetChanged)
            TextButton(
              onPressed: widget.onAdoptPlan,
              child: Text('采用计划目标 ${widget.settings.planTargetMl ?? ''} ml'),
            ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final t = int.tryParse(target.text), c = int.tryParse(cup.text);
              if (t == null || t < 500 || t > 6000 || t % 50 != 0) {
                setState(() => error = '目标需为 500–6000 ml，且按 50 ml 调整');
                return;
              }
              if (c == null || c < 50 || c > 2000) {
                setState(() => error = '默认杯量需为 50–2000 ml');
                return;
              }
              await widget.onSave({
                ...widget.settings.toJson(),
                'dailyTargetMl':
                    widget.settings.dailyTargetMl == null &&
                        t == widget.settings.effectiveTargetMl
                    ? null
                    : t,
                'defaultCupMl': c,
                'reminderEnabled': enabled,
                'reminderStartTime': _wire(reminderStart),
                'reminderEndTime': _wire(reminderEnd),
                'reminderIntervalMinutes': interval,
                'quietStartTime': quietEnabled ? _wire(quietStart) : null,
                'quietEndTime': quietEnabled ? _wire(quietEnd) : null,
              });
              if (context.mounted) Navigator.maybePop(context);
            },
            child: const Text('保存设置'),
          ),
        ],
      ),
    ),
  );
}
