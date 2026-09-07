import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_colors.dart';

String _dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class ProfileWizardPage extends StatefulWidget {
  const ProfileWizardPage({
    required this.api,
    required this.onCompleted,
    this.onBlocked,
    this.onCancel,
    super.key,
  });

  final ApiClient api;
  final VoidCallback onCompleted;
  final VoidCallback? onBlocked;
  final VoidCallback? onCancel;

  @override
  State<ProfileWizardPage> createState() => _ProfileWizardPageState();
}

class _ProfileWizardPageState extends State<ProfileWizardPage> {
  static const _titles = [
    '基础资料',
    '身体数据',
    '生活方式',
    '作息与运动',
    '饮食偏好',
    '健康目标',
    '风险评估',
  ];

  final _birthDate = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _waist = TextEditingController();
  final _otherAllergy = TextEditingController();
  final _otherAvoidFood = TextEditingController();
  final _targetWeight = TextEditingController();
  final _targetDate = TextEditingController(
    text: _dateText(DateTime.now().add(const Duration(days: 120))),
  );

  int _step = 0;
  bool _busy = false;
  bool _finished = false;
  String? _error;
  String? _resultMessage;
  bool _riskBlocked = false;
  String _sex = 'FEMALE';
  String _activity = 'LIGHT';
  String _workStyle = 'SEDENTARY';
  String _dietType = 'BALANCED';
  String _goalType = 'FAT_LOSS';
  bool _pregnant = false;
  bool _breastfeeding = false;
  bool _eatingDisorderRisk = false;
  bool _seriousDisease = false;
  bool _unsafeTarget = false;
  double _sleepHours = 7.5;
  int _exerciseDays = 3;
  final Set<String> _allergies = {'无'};
  final Set<String> _avoidFoods = {'无'};

  @override
  void initState() {
    super.initState();
    _resume();
  }

  Future<void> _resume() async {
    try {
      final data = await widget.api.profileCompleteness();
      if (mounted && data['complete'] != true) {
        setState(
          () =>
              _step = ((data['currentStep'] as num?)?.toInt() ?? 0).clamp(0, 6),
        );
      }
    } catch (_) {
      // A new profile starts from step one when the server has no saved progress.
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _birthDate,
      _height,
      _weight,
      _waist,
      _otherAllergy,
      _otherAvoidFood,
      _targetWeight,
      _targetDate,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _saveStep();
      if (!mounted) return;
      if (_step < 6) {
        setState(() => _step++);
      } else {
        setState(() => _finished = true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveStep() async {
    switch (_step) {
      case 0:
        await widget.api.saveProfile({
          'birthDate': _required(_birthDate, '请输入出生日期'),
          'sex': _sex,
          'currentStep': 1,
        });
      case 1:
        await widget.api.saveProfile({
          'heightCm': _number(_height, '请输入身高'),
          'currentStep': 2,
        });
        await widget.api.addMeasurement({
          'weightKg': _number(_weight, '请输入体重'),
          if (_waist.text.isNotEmpty) 'waistCm': double.parse(_waist.text),
        });
      case 2:
        await widget.api.saveProfile({
          'activityLevel': _activity,
          'workStyle': _workStyle,
          'currentStep': 3,
        });
      case 3:
        await widget.api.saveProfile({
          'sleepHours': _sleepHours,
          'exerciseDays': _exerciseDays,
          'currentStep': 4,
        });
      case 4:
        await widget.api.savePreferences({
          'dietType': _dietType,
          'allergies': _foodText(_allergies, _otherAllergy),
          'avoidFoods': _foodText(_avoidFoods, _otherAvoidFood),
        });
        await widget.api.saveProfile({'currentStep': 5});
      case 5:
        await widget.api.saveProfile({
          'goalType': _goalType,
          if (_targetWeight.text.isNotEmpty)
            'targetWeightKg': double.parse(_targetWeight.text),
          'targetDate': _required(_targetDate, '请输入目标日期'),
          'currentStep': 6,
        });
      case 6:
        final result = await widget.api.saveRisk({
          'pregnant': _pregnant,
          'breastfeeding': _breastfeeding,
          'eatingDisorderRisk': _eatingDisorderRisk,
          'seriousChronicDisease': _seriousDisease,
          'unsafeTarget': _unsafeTarget,
        });
        await widget.api.saveProfile({'currentStep': 7, 'completed': true});
        _resultMessage = result['message'] as String?;
        _riskBlocked = result['riskBlocked'] == true;
    }
  }

  String _required(TextEditingController controller, String message) {
    final value = controller.text.trim();
    if (value.isEmpty) throw FormatException(message);
    return value;
  }

  double _number(TextEditingController controller, String message) {
    final value = double.tryParse(controller.text.trim());
    if (value == null) throw FormatException(message);
    return value;
  }

  String _foodText(Set<String> selected, TextEditingController other) => [
    ...selected.where((item) => item != '无' && item != '其他'),
    if (selected.contains('其他') && other.text.trim().isNotEmpty)
      other.text.trim(),
  ].join('、');

  @override
  Widget build(BuildContext context) {
    if (_finished) return _result();
    return Scaffold(
      appBar: AppBar(
        title: const Text('建立健康档案'),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.onCancel != null)
            IconButton(
              tooltip: '暂时退出',
              onPressed: _busy ? null : widget.onCancel,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                LinearProgressIndicator(value: (_step + 1) / 7),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '第 ${_step + 1} 步，共 7 步',
                          style: const TextStyle(color: AppColors.green),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _titles[_step],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(_subtitle),
                        const SizedBox(height: 24),
                        _stepContent(),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                  child: Row(
                    children: [
                      if (_step > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _step--),
                            child: const Text('上一步'),
                          ),
                        ),
                      if (_step > 0) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : _next,
                          child: Text(
                            _busy
                                ? '保存中…'
                                : _step == 6
                                ? '完成分析'
                                : '保存并继续',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _subtitle => switch (_step) {
    0 => '用于评估基础健康范围。',
    1 => '数据越准确，后续计划越可靠。',
    2 => '了解你平时的活动量和工作状态。',
    3 => '结合睡眠和运动安排每日任务。',
    4 => '过敏信息会用于排除不合适的食物。',
    5 => '目标需要可执行，也需要安全。',
    _ => '以下信息仅用于安全拦截，不用于医疗诊断。',
  };

  Widget _stepContent() => switch (_step) {
    0 => Column(
      children: [
        _dateField(_birthDate, '出生日期', birthDate: true),
        const SizedBox(height: 18),
        _choices('性别', _sex, const {
          'FEMALE': '女',
          'MALE': '男',
          'OTHER': '其他',
        }, (value) => _sex = value),
      ],
    ),
    1 => Column(
      children: [
        _numberField(_height, '身高', unit: '厘米'),
        const SizedBox(height: 14),
        _numberField(
          _weight,
          '当前体重',
          unit: '千克',
          onChanged: (_) => _suggestTargetDate(),
        ),
        const SizedBox(height: 14),
        _numberField(_waist, '腰围（可选）', unit: '厘米'),
      ],
    ),
    2 => Column(
      children: [
        _choices('日常活动量', _activity, const {
          'LOW': '很少活动',
          'LIGHT': '轻度活动',
          'MODERATE': '中等活动',
          'HIGH': '高强度活动',
        }, (value) => _activity = value),
        const SizedBox(height: 14),
        _choices('工作状态', _workStyle, const {
          'SEDENTARY': '久坐',
          'MIXED': '坐立混合',
          'ACTIVE': '体力活动为主',
        }, (value) => _workStyle = value),
      ],
    ),
    3 => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('每晚睡眠：${_sleepHours.toStringAsFixed(1)} 小时'),
        Slider(
          value: _sleepHours,
          min: 4,
          max: 12,
          divisions: 16,
          label: '${_sleepHours.toStringAsFixed(1)} 小时',
          onChanged: (value) => setState(() => _sleepHours = value),
        ),
        const SizedBox(height: 18),
        _choices('每周运动天数', _exerciseDays.toString(), {
          for (var day = 0; day <= 7; day++) '$day': '$day 天',
        }, (value) => _exerciseDays = int.parse(value)),
      ],
    ),
    4 => Column(
      children: [
        _choices('饮食方式', _dietType, const {
          'BALANCED': '均衡饮食',
          'VEGETARIAN': '素食',
          'LOW_CARB': '低碳水',
          'HIGH_PROTEIN': '高蛋白',
        }, (value) => _dietType = value),
        const SizedBox(height: 18),
        _foodChoices('过敏食物', _allergies, const [
          '无',
          '乳制品',
          '鸡蛋',
          '花生',
          '坚果',
          '海鲜',
          '麸质',
          '其他',
        ], _otherAllergy),
        const SizedBox(height: 18),
        _foodChoices('不吃的食物', _avoidFoods, const [
          '无',
          '香菜',
          '葱姜蒜',
          '动物内脏',
          '辛辣食物',
          '其他',
        ], _otherAvoidFood),
      ],
    ),
    5 => Column(
      children: [
        _choices(
          '主要目标',
          _goalType,
          const {
            'FAT_LOSS': '减脂',
            'MUSCLE_GAIN': '增肌',
            'MAINTAIN': '维持体重',
            'BETTER_DIET': '改善饮食',
          },
          (value) {
            _goalType = value;
            if (value == 'MAINTAIN' || value == 'BETTER_DIET') {
              _targetWeight.clear();
            }
          },
        ),
        if (_goalType == 'FAT_LOSS' || _goalType == 'MUSCLE_GAIN') ...[
          const SizedBox(height: 14),
          _numberField(
            _targetWeight,
            '目标体重（可选）',
            unit: '千克',
            onChanged: (_) => _suggestTargetDate(),
          ),
        ],
        const SizedBox(height: 14),
        _dateField(_targetDate, '目标日期'),
        if (_goalType == 'FAT_LOSS') ...[
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('建议日期按每周约减重 0.5 千克估算，你可以调整。'),
          ),
        ],
      ],
    ),
    _ => Column(
      children: [
        _riskSwitch('处于孕期', _pregnant, (value) => _pregnant = value),
        _riskSwitch('处于哺乳期', _breastfeeding, (value) => _breastfeeding = value),
        _riskSwitch(
          '曾有进食障碍或相关风险',
          _eatingDisorderRisk,
          (value) => _eatingDisorderRisk = value,
        ),
        _riskSwitch(
          '有严重慢性病或正在接受治疗',
          _seriousDisease,
          (value) => _seriousDisease = value,
        ),
        _riskSwitch(
          '希望进行极端节食或快速减重',
          _unsafeTarget,
          (value) => _unsafeTarget = value,
        ),
      ],
    ),
  };

  Widget _choices(
    String label,
    String value,
    Map<String, String> values,
    ValueChanged<String> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: values.entries
            .map(
              (entry) => ChoiceChip(
                label: Text(entry.value),
                selected: value == entry.key,
                onSelected: (_) => setState(() => onChanged(entry.key)),
              ),
            )
            .toList(),
      ),
    ],
  );

  Widget _dateField(
    TextEditingController controller,
    String label, {
    bool birthDate = false,
  }) => TextField(
    controller: controller,
    readOnly: true,
    onTap: () => _pickDate(controller, birthDate: birthDate),
    decoration: InputDecoration(
      labelText: label,
      hintText: '点击选择',
      suffixIcon: const Icon(Icons.calendar_today_outlined),
    ),
  );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    required String unit,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    stylusHandwritingEnabled: false,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: '请输入',
      suffixText: unit,
    ),
  );

  Widget _foodChoices(
    String label,
    Set<String> selected,
    List<String> options,
    TextEditingController other,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options
            .map(
              (item) => FilterChip(
                label: Text(item),
                selected: selected.contains(item),
                onSelected: (_) => setState(() {
                  if (item == '无') {
                    selected
                      ..clear()
                      ..add('无');
                    other.clear();
                  } else {
                    selected.remove('无');
                    selected.contains(item)
                        ? selected.remove(item)
                        : selected.add(item);
                    if (selected.isEmpty) selected.add('无');
                  }
                }),
              ),
            )
            .toList(),
      ),
      if (selected.contains('其他')) ...[
        const SizedBox(height: 12),
        TextField(
          controller: other,
          stylusHandwritingEnabled: false,
          decoration: const InputDecoration(labelText: '填写其他食物'),
        ),
      ],
    ],
  );

  Future<void> _pickDate(
    TextEditingController controller, {
    required bool birthDate,
  }) async {
    final now = DateTime.now();
    final parsed = DateTime.tryParse(controller.text);
    final first = birthDate ? DateTime(1900) : now.add(const Duration(days: 1));
    final last = birthDate ? now : DateTime(now.year + 5, now.month, now.day);
    final initial =
        parsed != null && !parsed.isBefore(first) && !parsed.isAfter(last)
        ? parsed
        : birthDate
        ? DateTime(now.year - 30, now.month, now.day)
        : now.add(const Duration(days: 120));
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (context) => _DateWheelPicker(
        title: birthDate ? '选择出生日期' : '选择目标日期',
        initialDate: initial,
        minimumDate: first,
        maximumDate: last,
      ),
    );
    if (selected != null) setState(() => controller.text = _dateText(selected));
  }

  void _suggestTargetDate() {
    if (_goalType != 'FAT_LOSS') return;
    final current = double.tryParse(_weight.text);
    final target = double.tryParse(_targetWeight.text);
    if (current == null || target == null || target >= current) return;
    final days = (((current - target) / 0.5) * 7).ceil().clamp(28, 730);
    _targetDate.text = _dateText(DateTime.now().add(Duration(days: days)));
  }

  Widget _riskSwitch(String title, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        value: value,
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        onChanged: (next) => setState(() => onChanged(next)),
      );

  Widget _result() => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.verified_outlined,
                  size: 64,
                  color: AppColors.green,
                ),
                const SizedBox(height: 20),
                Text(
                  '档案已建立',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  _resultMessage ?? '数据已安全保存，可以开始制定你的生活计划。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _riskBlocked
                        ? widget.onBlocked ?? widget.onCompleted
                        : widget.onCompleted,
                    child: Text(_riskBlocked ? '返回首页' : '进入今日计划'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DateWheelPicker extends StatefulWidget {
  const _DateWheelPicker({
    required this.title,
    required this.initialDate,
    required this.minimumDate,
    required this.maximumDate,
  });

  final String title;
  final DateTime initialDate;
  final DateTime minimumDate;
  final DateTime maximumDate;

  @override
  State<_DateWheelPicker> createState() => _DateWheelPickerState();
}

class _DateWheelPickerState extends State<_DateWheelPicker> {
  late int _year;
  late int _month;
  late int _day;
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _dayController;

  List<int> get _years => [
    for (
      var year = widget.minimumDate.year;
      year <= widget.maximumDate.year;
      year++
    )
      year,
  ];

  List<int> get _months {
    final first = _year == widget.minimumDate.year
        ? widget.minimumDate.month
        : 1;
    final last = _year == widget.maximumDate.year
        ? widget.maximumDate.month
        : 12;
    return [for (var month = first; month <= last; month++) month];
  }

  List<int> get _days {
    final first =
        _year == widget.minimumDate.year && _month == widget.minimumDate.month
        ? widget.minimumDate.day
        : 1;
    final monthEnd = DateTime(_year, _month + 1, 0).day;
    final last =
        _year == widget.maximumDate.year && _month == widget.maximumDate.month
        ? widget.maximumDate.day
        : monthEnd;
    return [for (var day = first; day <= last; day++) day];
  }

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _day = widget.initialDate.day;
    _normalize();
    _yearController = FixedExtentScrollController(
      initialItem: _years.indexOf(_year),
    );
    _monthController = FixedExtentScrollController(
      initialItem: _months.indexOf(_month),
    );
    _dayController = FixedExtentScrollController(
      initialItem: _days.indexOf(_day),
    );
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  void _normalize() {
    final months = _months;
    _month = _month.clamp(months.first, months.last);
    final days = _days;
    _day = _day.clamp(days.first, days.last);
  }

  void _syncWheels() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _monthController.jumpToItem(_months.indexOf(_month));
      _dayController.jumpToItem(_days.indexOf(_day));
    });
  }

  Widget _wheel(
    List<int> values,
    FixedExtentScrollController controller,
    ValueChanged<int> onChanged,
  ) => CupertinoPicker(
    scrollController: controller,
    itemExtent: 46,
    useMagnifier: true,
    magnification: 1.08,
    onSelectedItemChanged: (index) => onChanged(values[index]),
    children: values.map((value) => Center(child: Text('$value'))).toList(),
  );

  @override
  Widget build(BuildContext context) {
    final months = _months;
    final days = _days;
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, DateTime(_year, _month, _day)),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            const Row(
              children: [
                Expanded(child: Center(child: Text('年'))),
                Expanded(child: Center(child: Text('月'))),
                Expanded(child: Center(child: Text('日'))),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _wheel(_years, _yearController, (value) {
                      setState(() {
                        _year = value;
                        _normalize();
                      });
                      _syncWheels();
                    }),
                  ),
                  Expanded(
                    child: _wheel(months, _monthController, (value) {
                      setState(() {
                        _month = value;
                        _normalize();
                      });
                      _syncWheels();
                    }),
                  ),
                  Expanded(
                    child: _wheel(days, _dayController, (value) {
                      setState(() => _day = value);
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
