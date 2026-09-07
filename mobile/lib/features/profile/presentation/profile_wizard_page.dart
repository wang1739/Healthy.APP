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
    super.key,
  });

  final ApiClient api;
  final VoidCallback onCompleted;

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

  final _birthDate = TextEditingController(text: '1995-01-01');
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _waist = TextEditingController();
  final _sleep = TextEditingController(text: '7.5');
  final _exerciseDays = TextEditingController(text: '3');
  final _allergies = TextEditingController();
  final _avoidFoods = TextEditingController();
  final _targetWeight = TextEditingController();
  final _targetDate = TextEditingController(
    text: _dateText(DateTime.now().add(const Duration(days: 120))),
  );

  int _step = 0;
  bool _busy = false;
  bool _finished = false;
  String? _error;
  String? _resultMessage;
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
      _sleep,
      _exerciseDays,
      _allergies,
      _avoidFoods,
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
          'sleepHours': _number(_sleep, '请输入睡眠时长'),
          'exerciseDays': _integer(_exerciseDays, '请输入每周运动天数'),
          'currentStep': 4,
        });
      case 4:
        await widget.api.savePreferences({
          'dietType': _dietType,
          'allergies': _allergies.text.trim(),
          'avoidFoods': _avoidFoods.text.trim(),
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

  int _integer(TextEditingController controller, String message) {
    final value = int.tryParse(controller.text.trim());
    if (value == null) throw FormatException(message);
    return value;
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _result();
    return Scaffold(
      appBar: AppBar(
        title: const Text('建立健康档案'),
        automaticallyImplyLeading: false,
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
        _field(_birthDate, '出生日期', hint: '1995-01-01'),
        const SizedBox(height: 14),
        _dropdown('性别', _sex, const {
          'FEMALE': '女',
          'MALE': '男',
          'OTHER': '其他',
        }, (value) => _sex = value),
      ],
    ),
    1 => Column(
      children: [
        _numberField(_height, '身高（cm）'),
        const SizedBox(height: 14),
        _numberField(_weight, '当前体重（kg）'),
        const SizedBox(height: 14),
        _numberField(_waist, '腰围（cm，可选）'),
      ],
    ),
    2 => Column(
      children: [
        _dropdown('日常活动量', _activity, const {
          'LOW': '很少活动',
          'LIGHT': '轻度活动',
          'MODERATE': '中等活动',
          'HIGH': '高强度活动',
        }, (value) => _activity = value),
        const SizedBox(height: 14),
        _dropdown('工作状态', _workStyle, const {
          'SEDENTARY': '久坐',
          'MIXED': '坐立混合',
          'ACTIVE': '体力活动为主',
        }, (value) => _workStyle = value),
      ],
    ),
    3 => Column(
      children: [
        _numberField(_sleep, '每晚睡眠时长（小时）'),
        const SizedBox(height: 14),
        _numberField(_exerciseDays, '每周运动天数', integer: true),
      ],
    ),
    4 => Column(
      children: [
        _dropdown('饮食方式', _dietType, const {
          'BALANCED': '均衡饮食',
          'VEGETARIAN': '素食',
          'LOW_CARB': '低碳水',
          'HIGH_PROTEIN': '高蛋白',
        }, (value) => _dietType = value),
        const SizedBox(height: 14),
        _field(_allergies, '过敏食物', hint: '没有可留空'),
        const SizedBox(height: 14),
        _field(_avoidFoods, '不吃的食物', hint: '没有可留空'),
      ],
    ),
    5 => Column(
      children: [
        _dropdown('主要目标', _goalType, const {
          'FAT_LOSS': '减脂',
          'MUSCLE_GAIN': '增肌',
          'MAINTAIN': '维持体重',
          'BETTER_DIET': '改善饮食',
        }, (value) => _goalType = value),
        const SizedBox(height: 14),
        _numberField(_targetWeight, '目标体重（kg，可选）'),
        const SizedBox(height: 14),
        _field(_targetDate, '目标日期', hint: '例如 2027-01-01'),
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

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
  }) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool integer = false,
  }) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(integer ? r'\d' : r'[\d.]')),
    ],
    decoration: InputDecoration(labelText: label),
  );

  Widget _dropdown(
    String label,
    String value,
    Map<String, String> values,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values.entries
        .map(
          (entry) =>
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        )
        .toList(),
    onChanged: (next) {
      if (next != null) setState(() => onChanged(next));
    },
  );

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
                    onPressed: widget.onCompleted,
                    child: const Text('进入今日计划'),
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
