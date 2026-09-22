enum ProfileSection {
  basic('basic', '基本信息'),
  body('body', '身体测量'),
  lifestyle('lifestyle', '生活方式'),
  goal('goal', '健康目标'),
  preferences('preferences', '饮食偏好'),
  risk('risk', '风险评估');

  const ProfileSection(this.key, this.title);
  final String key;
  final String title;
}

class BodyMeasurement {
  const BodyMeasurement({
    required this.id,
    required this.weightKg,
    required this.measuredAt,
    this.waistCm,
    this.bodyFatPercent,
  });

  factory BodyMeasurement.fromJson(Map<String, dynamic> json) =>
      BodyMeasurement(
        id: _text(json, 'id') ?? '',
        weightKg: _number(json, 'weightKg', 'weight_kg') ?? 0,
        waistCm: _number(json, 'waistCm', 'waist_cm'),
        bodyFatPercent: _number(json, 'bodyFatPercent', 'body_fat_percent'),
        measuredAt: DateTime.tryParse(
          _text(json, 'measuredAt', 'measured_at') ?? '',
        ),
      );

  final String id;
  final double weightKg;
  final double? waistCm;
  final double? bodyFatPercent;
  final DateTime? measuredAt;
}

class ProfileData {
  const ProfileData({
    required this.planNeedsRecalculation,
    required this.birthDate,
    required this.sex,
    required this.metabolicBasis,
    required this.heightCm,
    required this.measurements,
    required this.activityLevel,
    required this.workStyle,
    required this.sleepHours,
    required this.exerciseDays,
    required this.dietType,
    required this.allergies,
    required this.avoidFoods,
    required this.goalType,
    required this.targetWeightKg,
    required this.targetDate,
    required this.pregnant,
    required this.breastfeeding,
    required this.eatingDisorderRisk,
    required this.seriousChronicDisease,
    required this.unsafeTarget,
    required this.riskBlocked,
  });

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    final sections = _map(json['sections']);
    final basic = _section(sections, json, 'basic', 'basicInfo');
    final body = _section(sections, json, 'body', 'bodyData');
    final lifestyle = _section(sections, json, 'lifestyle');
    final preferences = _section(
      sections,
      json,
      'preferences',
      'dietaryPreferences',
    );
    final goal = _section(sections, json, 'goal', 'healthGoal');
    final risk = _section(sections, json, 'risk', 'riskInfo');
    final history = body['measurements'] ?? json['measurements'];
    return ProfileData(
      planNeedsRecalculation:
          json['planNeedsRecalculation'] == true ||
          json['plan_needs_recalculation'] == true,
      birthDate: _text(basic, 'birthDate', 'birth_date'),
      sex: _text(basic, 'sex') ?? 'FEMALE',
      metabolicBasis: _text(basic, 'metabolicBasis', 'metabolic_basis'),
      heightCm: _number(body, 'heightCm', 'height_cm'),
      measurements: history is List
          ? history
                .whereType<Map>()
                .map(
                  (item) =>
                      BodyMeasurement.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      activityLevel:
          _text(lifestyle, 'activityLevel', 'activity_level') ?? 'LIGHT',
      workStyle: _text(lifestyle, 'workStyle', 'work_style') ?? 'SEDENTARY',
      sleepHours: _number(lifestyle, 'sleepHours', 'sleep_hours') ?? 7.5,
      exerciseDays:
          _number(lifestyle, 'exerciseDays', 'exercise_days')?.round() ?? 3,
      dietType: _text(preferences, 'dietType', 'diet_type') ?? 'BALANCED',
      allergies: _strings(preferences['allergies']),
      avoidFoods: _strings(
        preferences['avoidFoods'] ?? preferences['avoid_foods'],
      ),
      goalType: _text(goal, 'goalType', 'goal_type') ?? 'FAT_LOSS',
      targetWeightKg: _number(goal, 'targetWeightKg', 'target_weight_kg'),
      targetDate: _text(goal, 'targetDate', 'target_date'),
      pregnant: risk['pregnant'] == true,
      breastfeeding: risk['breastfeeding'] == true,
      eatingDisorderRisk:
          risk['eatingDisorderRisk'] == true ||
          risk['eating_disorder_risk'] == true,
      seriousChronicDisease:
          risk['seriousChronicDisease'] == true ||
          risk['serious_chronic_disease'] == true,
      unsafeTarget:
          risk['unsafeTarget'] == true || risk['unsafe_target'] == true,
      riskBlocked: risk['riskBlocked'] == true || risk['risk_blocked'] == true,
    );
  }

  final bool planNeedsRecalculation;
  final String? birthDate;
  final String sex;
  final String? metabolicBasis;
  final double? heightCm;
  final List<BodyMeasurement> measurements;
  final String activityLevel;
  final String workStyle;
  final double sleepHours;
  final int exerciseDays;
  final String dietType;
  final List<String> allergies;
  final List<String> avoidFoods;
  final String goalType;
  final double? targetWeightKg;
  final String? targetDate;
  final bool pregnant;
  final bool breastfeeding;
  final bool eatingDisorderRisk;
  final bool seriousChronicDisease;
  final bool unsafeTarget;
  final bool riskBlocked;

  ProfileData withMeasurements(List<BodyMeasurement> values) => ProfileData(
    planNeedsRecalculation: planNeedsRecalculation,
    birthDate: birthDate,
    sex: sex,
    metabolicBasis: metabolicBasis,
    heightCm: heightCm,
    measurements: values,
    activityLevel: activityLevel,
    workStyle: workStyle,
    sleepHours: sleepHours,
    exerciseDays: exerciseDays,
    dietType: dietType,
    allergies: allergies,
    avoidFoods: avoidFoods,
    goalType: goalType,
    targetWeightKg: targetWeightKg,
    targetDate: targetDate,
    pregnant: pregnant,
    breastfeeding: breastfeeding,
    eatingDisorderRisk: eatingDisorderRisk,
    seriousChronicDisease: seriousChronicDisease,
    unsafeTarget: unsafeTarget,
    riskBlocked: riskBlocked,
  );

  Object? value(String key) => switch (key) {
    'birthDate' => birthDate,
    'sex' => sex,
    'metabolicBasis' => metabolicBasis,
    'heightCm' => heightCm,
    'weightKg' => measurements.isEmpty ? null : measurements.first.weightKg,
    'activityLevel' => activityLevel,
    'goalType' => goalType,
    'targetWeightKg' => targetWeightKg,
    'targetDate' => targetDate,
    _ => null,
  };
}

Map<String, dynamic> _section(
  Map<String, dynamic> sections,
  Map<String, dynamic> root,
  String key, [
  String? apiKey,
]) {
  final value = sections[key] ?? root[apiKey ?? key] ?? root[key];
  return value is Map ? Map<String, dynamic>.from(value) : root;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

String? _text(Map<String, dynamic> json, String key, [String? fallback]) =>
    (json[key] ?? (fallback == null ? null : json[fallback]))?.toString();

double? _number(Map<String, dynamic> json, String key, [String? fallback]) {
  final value = json[key] ?? (fallback == null ? null : json[fallback]);
  return value is num ? value.toDouble() : double.tryParse('$value');
}

List<String> _strings(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return value
          ?.toString()
          .split(RegExp(r'[、,，]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList() ??
      const [];
}
