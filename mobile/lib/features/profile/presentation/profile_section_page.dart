import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/profile/application/profile_controller.dart';
import 'package:healthy/features/profile/domain/profile_data.dart';

class ProfileSectionPage extends StatefulWidget {
  const ProfileSectionPage({
    required this.section,
    required this.controller,
    super.key,
  });

  final ProfileSection section;
  final ProfileController controller;

  @override
  State<ProfileSectionPage> createState() => _ProfileSectionPageState();
}

class _ProfileSectionPageState extends State<ProfileSectionPage> {
  late final TextEditingController _birthDate;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _waist;
  late final TextEditingController _bodyFat;
  late final TextEditingController _sleep;
  late final TextEditingController _allergies;
  late final TextEditingController _avoidFoods;
  late final TextEditingController _targetWeight;
  late final TextEditingController _targetDate;
  late String _sex;
  String? _metabolicBasis;
  late String _activityLevel;
  late String _workStyle;
  late int _exerciseDays;
  late String _dietType;
  late bool _pregnant;
  late bool _breastfeeding;
  late bool _eatingDisorderRisk;
  late bool _seriousChronicDisease;
  late bool _unsafeTarget;
  bool _saving = false;

  ProfileData get data => widget.controller.state.data!;

  @override
  void initState() {
    super.initState();
    final latest = data.measurements.isEmpty ? null : data.measurements.first;
    _birthDate = TextEditingController(text: data.birthDate);
    _height = TextEditingController(text: _display(data.heightCm));
    _weight = TextEditingController(text: _display(latest?.weightKg));
    _waist = TextEditingController(text: _display(latest?.waistCm));
    _bodyFat = TextEditingController(text: _display(latest?.bodyFatPercent));
    _sleep = TextEditingController(text: _display(data.sleepHours));
    _allergies = TextEditingController(text: data.allergies.join('、'));
    _avoidFoods = TextEditingController(text: data.avoidFoods.join('、'));
    _targetWeight = TextEditingController(text: _display(data.targetWeightKg));
    _targetDate = TextEditingController(text: data.targetDate);
    _sex = data.sex;
    _metabolicBasis = data.metabolicBasis;
    _activityLevel = data.activityLevel;
    _workStyle = data.workStyle;
    _exerciseDays = data.exerciseDays;
    _dietType = data.dietType;
    _pregnant = data.pregnant;
    _breastfeeding = data.breastfeeding;
    _eatingDisorderRisk = data.eatingDisorderRisk;
    _seriousChronicDisease = data.seriousChronicDisease;
    _unsafeTarget = data.unsafeTarget;
  }

  @override
  void dispose() {
    for (final controller in [
      _birthDate,
      _height,
      _weight,
      _waist,
      _bodyFat,
      _sleep,
      _allergies,
      _avoidFoods,
      _targetWeight,
      _targetDate,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.section.title)),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        _content(),
        if (widget.controller.state.error != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.controller.state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.large),
        if (widget.section != ProfileSection.body)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存…' : '保存${widget.section.title}'),
          ),
      ],
    ),
  );

  Widget _content() => switch (widget.section) {
    ProfileSection.basic => _basic(),
    ProfileSection.body => _body(),
    ProfileSection.lifestyle => _lifestyle(),
    ProfileSection.goal => _goal(),
    ProfileSection.preferences => _preferences(),
    ProfileSection.risk => _risk(),
  };

  Widget _basic() => Column(
    children: [
      _dateField(_birthDate, '出生日期', past: true),
      const SizedBox(height: 14),
      _select(
        label: '性别',
        value: _sex,
        values: const {'FEMALE': '女', 'MALE': '男', 'OTHER': '其他'},
        onChanged: (value) => setState(() {
          _sex = value;
          if (value != 'OTHER') _metabolicBasis = value;
        }),
      ),
      if (_sex == 'OTHER') ...[
        const SizedBox(height: 14),
        _select(
          label: '代谢计算依据',
          value: _metabolicBasis ?? 'FEMALE',
          values: const {'FEMALE': '女性公式', 'MALE': '男性公式'},
          onChanged: (value) => setState(() => _metabolicBasis = value),
        ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('仅用于估算能量，不会改变你的性别显示。'),
        ),
      ],
    ],
  );

  Widget _body() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _numberField(_height, '身高', '厘米'),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '正在保存…' : '保存身高'),
      ),
      const SizedBox(height: 24),
      Text('新增测量', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      _numberField(_weight, '当前体重', '千克'),
      const SizedBox(height: 12),
      _numberField(_waist, '腰围（可选）', '厘米'),
      const SizedBox(height: 12),
      _numberField(_bodyFat, '体脂率（可选）', '%'),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: _saving ? null : _addMeasurement,
        child: const Text('新增测量'),
      ),
      const SizedBox(height: 24),
      Text('测量历史', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (data.measurements.isEmpty)
        const Text('还没有测量记录')
      else
        ...data.measurements.map(
          (item) => Card(
            child: ListTile(
              title: Text('${_display(item.weightKg)} 千克'),
              subtitle: Text(
                [
                  if (item.waistCm != null) '腰围 ${_display(item.waistCm)} 厘米',
                  if (item.bodyFatPercent != null)
                    '体脂 ${_display(item.bodyFatPercent)}%',
                  if (item.measuredAt != null) _dateTime(item.measuredAt!),
                ].join(' · '),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _lifestyle() => Column(
    children: [
      _select(
        label: '日常活动量',
        value: _activityLevel,
        values: const {
          'LOW': '很少活动',
          'LIGHT': '轻度活动',
          'MODERATE': '中等活动',
          'HIGH': '高强度活动',
        },
        onChanged: (value) => setState(() => _activityLevel = value),
      ),
      const SizedBox(height: 14),
      _select(
        label: '工作状态',
        value: _workStyle,
        values: const {'SEDENTARY': '久坐', 'MIXED': '坐立混合', 'ACTIVE': '体力活动为主'},
        onChanged: (value) => setState(() => _workStyle = value),
      ),
      const SizedBox(height: 14),
      _numberField(_sleep, '每日睡眠', '小时'),
      const SizedBox(height: 14),
      _select(
        label: '每周运动天数',
        value: '$_exerciseDays',
        values: {for (var day = 0; day <= 7; day++) '$day': '$day 天'},
        onChanged: (value) => setState(() => _exerciseDays = int.parse(value)),
      ),
    ],
  );

  Widget _preferences() => Column(
    children: [
      _select(
        label: '饮食方式',
        value: _dietType,
        values: const {
          'BALANCED': '均衡饮食',
          'VEGETARIAN': '素食',
          'LOW_CARB': '低碳水',
          'HIGH_PROTEIN': '高蛋白',
        },
        onChanged: (value) => setState(() => _dietType = value),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _allergies,
        decoration: const InputDecoration(
          labelText: '过敏食物',
          helperText: '多个食物请用顿号或逗号分隔',
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _avoidFoods,
        decoration: const InputDecoration(
          labelText: '不吃的食物',
          helperText: '保存后立即用于饮食建议',
        ),
      ),
    ],
  );

  Widget _goal() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.check_circle_outline),
        title: Text('减脂'),
        subtitle: Text('当前已开放'),
      ),
      const Text('增肌、维持体重和改善饮食等其他目标尚未开放。'),
      const SizedBox(height: 14),
      _numberField(_targetWeight, '目标体重（可选）', '千克'),
      const SizedBox(height: 14),
      _dateField(_targetDate, '目标日期'),
    ],
  );

  Widget _risk() => Column(
    children: [
      _switch('处于孕期', _pregnant, (value) => _pregnant = value),
      _switch('处于哺乳期', _breastfeeding, (value) => _breastfeeding = value),
      _switch(
        '曾有进食障碍或相关风险',
        _eatingDisorderRisk,
        (value) => _eatingDisorderRisk = value,
      ),
      _switch(
        '有严重慢性病或正在接受治疗',
        _seriousChronicDisease,
        (value) => _seriousChronicDisease = value,
      ),
      _switch('希望进行极端节食或快速减重', _unsafeTarget, (value) => _unsafeTarget = value),
    ],
  );

  Widget _switch(String title, bool value, ValueChanged<bool> changed) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: value,
        onChanged: (next) => setState(() => changed(next)),
      );

  Widget _select({
    required String label,
    required String value,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
  }) => DropdownButtonFormField<String>(
    initialValue: values.containsKey(value) ? value : values.keys.first,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: values.entries
        .map(
          (item) => DropdownMenuItem(value: item.key, child: Text(item.value)),
        )
        .toList(),
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );

  Widget _numberField(
    TextEditingController controller,
    String label,
    String unit,
  ) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    decoration: InputDecoration(labelText: label, suffixText: unit),
  );

  Widget _dateField(
    TextEditingController controller,
    String label, {
    bool past = false,
  }) => TextField(
    controller: controller,
    readOnly: true,
    onTap: () => _pickDate(controller, past: past),
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: const Icon(Icons.calendar_today_outlined),
    ),
  );

  Future<void> _pickDate(
    TextEditingController controller, {
    required bool past,
  }) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse(controller.text) ??
          (past
              ? DateTime(now.year - 30, now.month, now.day)
              : now.add(const Duration(days: 120))),
      firstDate: past ? DateTime(1900) : now.add(const Duration(days: 1)),
      lastDate: past ? now : DateTime(now.year + 5, now.month, now.day),
      helpText: past ? '选择出生日期' : '选择目标日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected != null) {
      controller.text =
          '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    Map<String, dynamic> payload;
    try {
      payload = switch (widget.section) {
        ProfileSection.basic => {
          'birthDate': _required(_birthDate, '请选择出生日期'),
          'sex': _sex,
          'metabolicBasis': _sex == 'OTHER' ? _metabolicBasis : _sex,
        },
        ProfileSection.body => {'heightCm': _requiredNumber(_height, '请输入身高')},
        ProfileSection.lifestyle => {
          'activityLevel': _activityLevel,
          'workStyle': _workStyle,
          'sleepHours': _requiredNumber(_sleep, '请输入睡眠时长'),
          'exerciseDays': _exerciseDays,
        },
        ProfileSection.preferences => {
          'dietType': _dietType,
          'allergies': _allergies.text.trim(),
          'avoidFoods': _avoidFoods.text.trim(),
        },
        ProfileSection.goal => {
          'goalType': 'FAT_LOSS',
          if (_targetWeight.text.trim().isNotEmpty)
            'targetWeightKg': _requiredNumber(_targetWeight, '请输入目标体重'),
          'targetDate': _required(_targetDate, '请选择目标日期'),
        },
        ProfileSection.risk => {
          'pregnant': _pregnant,
          'breastfeeding': _breastfeeding,
          'eatingDisorderRisk': _eatingDisorderRisk,
          'seriousChronicDisease': _seriousChronicDisease,
          'unsafeTarget': _unsafeTarget,
        },
      };
    } on FormatException catch (error) {
      _message(error.message);
      return;
    }
    setState(() => _saving = true);
    final result = await widget.controller.save(widget.section.key, payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == ProfileSaveResult.failed) return;
    if (result == ProfileSaveResult.recalculationRequired) {
      await _showRecalculationNotice();
      return;
    }
    final message = switch (widget.section) {
      ProfileSection.preferences => '饮食偏好已更新，请刷新饮食建议',
      ProfileSection.risk when widget.controller.state.data!.riskBlocked =>
        '风险信息已更新，普通计划已暂停；如有需要，请咨询医生或注册营养师',
      _ => '保存成功',
    };
    _message(message);
  }

  Future<void> _addMeasurement() async {
    Map<String, dynamic> payload;
    try {
      payload = {
        'weightKg': _requiredNumber(_weight, '请输入体重'),
        if (_waist.text.trim().isNotEmpty)
          'waistCm': _requiredNumber(_waist, '请输入正确的腰围'),
        if (_bodyFat.text.trim().isNotEmpty)
          'bodyFatPercent': _requiredNumber(_bodyFat, '请输入正确的体脂率'),
      };
    } on FormatException catch (error) {
      _message(error.message);
      return;
    }
    setState(() => _saving = true);
    final result = await widget.controller.addMeasurement(payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == ProfileSaveResult.recalculationRequired) {
      await _showRecalculationNotice();
    }
  }

  Future<void> _showRecalculationNotice() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('计划需要重新计算'),
      content: const Text('关键档案已保存。确认使用新计划前，旧计划继续显示并保留历史。'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );

  String _required(TextEditingController controller, String message) {
    final value = controller.text.trim();
    if (value.isEmpty) throw FormatException(message);
    return value;
  }

  double _requiredNumber(TextEditingController controller, String message) {
    final value = double.tryParse(controller.text.trim());
    if (value == null) throw FormatException(message);
    return value;
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _display(num? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
