import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/profile/application/profile_controller.dart';

class _FakeApi extends ApiClient {
  Map<String, dynamic> profile = {
    'profileVersion': 7,
    'planNeedsRecalculation': false,
    'basicInfo': {'birthDate': '1996-05-12', 'sex': 'FEMALE'},
    'bodyData': {'heightCm': 165},
    'lifestyle': {
      'activityLevel': 'LIGHT',
      'workStyle': 'SEDENTARY',
      'sleepHours': 7.5,
      'exerciseDays': 3,
    },
    'dietaryPreferences': {
      'dietType': 'BALANCED',
      'allergies': '',
      'avoidFoods': '',
    },
    'healthGoal': {
      'goalType': 'FAT_LOSS',
      'targetWeightKg': 58,
      'targetDate': '2027-01-20',
    },
    'riskInfo': {
      'pregnant': false,
      'breastfeeding': false,
      'eatingDisorderRisk': false,
      'seriousChronicDisease': false,
      'unsafeTarget': false,
      'riskBlocked': false,
    },
  };
  String? savedSection;
  Map<String, dynamic>? savedBody;
  int? savedExpectedVersion;
  final savedExpectedVersions = <int>[];
  bool fail = false;
  bool conflict = false;
  int reads = 0;
  int measurementReads = 0;
  List<Map<String, dynamic>> measurements = [
    {'id': 'm1', 'weightKg': 62.5, 'measuredAt': '2026-09-20T08:00:00Z'},
  ];

  @override
  Future<Map<String, dynamic>> getProfileSections() async {
    reads++;
    return profile;
  }

  @override
  Future<Map<String, dynamic>> saveProfileSection(
    String section,
    Map<String, dynamic> data, {
    required int expectedVersion,
  }) async {
    savedSection = section;
    savedBody = data;
    savedExpectedVersion = expectedVersion;
    savedExpectedVersions.add(expectedVersion);
    if (fail) throw DioException(requestOptions: RequestOptions());
    if (conflict) {
      profile = {
        ...profile,
        'profileVersion': 9,
        'basicInfo': {
          'birthDate': '1994-04-11',
          'sex': 'FEMALE',
          'metabolicBasis': 'FEMALE',
        },
      };
      final request = RequestOptions();
      throw DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {
            'code': 'PROFILE_VERSION_CONFLICT',
            'message': '健康档案已更新，请刷新后重试',
          },
        ),
      );
    }
    final latestMeasurement = section == 'body' && data['weightKg'] != null
        ? {'id': 'm2', ...data, 'measuredAt': '2026-09-22T08:00:00Z'}
        : null;
    if (latestMeasurement != null) {
      measurements = [latestMeasurement, ...measurements];
    }
    profile = {
      ...profile,
      'profileVersion': expectedVersion + 1,
      'planNeedsRecalculation':
          profile['planNeedsRecalculation'] == true ||
          section == 'basic' ||
          latestMeasurement != null,
      if (section == 'basic')
        'basicInfo': {
          ...Map<String, dynamic>.from(profile['basicInfo'] as Map),
          ...data,
        },
      if (section == 'body')
        'bodyData': {
          ...Map<String, dynamic>.from(profile['bodyData'] as Map),
          if (data['heightCm'] != null) 'heightCm': data['heightCm'],
          'latestMeasurement': ?latestMeasurement,
        },
    };
    return profile;
  }

  @override
  Future<List<Map<String, dynamic>>> getProfileMeasurements() async {
    measurementReads++;
    return measurements;
  }
}

class _DelayedReadApi extends _FakeApi {
  Completer<Map<String, dynamic>>? delayedSections;

  @override
  Future<Map<String, dynamic>> getProfileSections() {
    final delayed = delayedSections;
    if (delayed != null) {
      reads++;
      return delayed.future;
    }
    return super.getProfileSections();
  }
}

void main() {
  test('加载档案及身体测量历史', () async {
    final controller = ProfileController(_FakeApi());
    await controller.load();
    expect(controller.state.data!.birthDate, '1996-05-12');
    expect(controller.state.data!.measurements.single.weightKg, 62.5);
  });

  test('仅提交当前分区并返回是否需要重算', () async {
    final api = _FakeApi();
    final controller = ProfileController(api);
    await controller.load();
    final result = await controller.save('basic', {
      'birthDate': '1995-05-12',
      'sex': 'FEMALE',
    });
    expect(result, ProfileSaveResult.recalculationRequired);
    expect(api.savedSection, 'basic');
    expect(api.savedBody, {'birthDate': '1995-05-12', 'sex': 'FEMALE'});
    expect(api.savedExpectedVersion, 7);
    expect(controller.state.data!.profileVersion, 8);
    expect(api.reads, 1);
  });

  test('六分区连续保存始终使用最新档案版本', () async {
    final api = _FakeApi();
    final controller = ProfileController(api);
    await controller.load();

    await controller.save('basic', {'birthDate': '1995-05-12'});
    await controller.save('body', {'heightCm': 166});
    await controller.save('lifestyle', {'workStyle': 'ACTIVE'});
    await controller.save('preferences', {'dietType': 'BALANCED'});
    await controller.save('goal', {'goalType': 'FAT_LOSS'});
    await controller.save('risk', {
      'pregnant': false,
      'breastfeeding': false,
      'eatingDisorderRisk': true,
      'seriousChronicDisease': false,
      'unsafeTarget': false,
    });

    expect(api.savedExpectedVersions, [7, 8, 9, 10, 11, 12]);
    expect(controller.state.data!.profileVersion, 13);
    expect(api.reads, 1);
  });

  test('新增测量复用身体分区版本写入并直接合并权威响应', () async {
    final api = _FakeApi();
    final controller = ProfileController(api);
    await controller.load();

    final result = await controller.addMeasurement({
      'weightKg': 61.8,
      'waistCm': 71,
    });

    expect(result, ProfileSaveResult.recalculationRequired);
    expect(api.savedSection, 'body');
    expect(api.savedExpectedVersion, 7);
    expect(api.reads, 1);
    expect(controller.state.data!.profileVersion, 8);
    expect(controller.state.data!.measurements.first.id, 'm2');
    expect(controller.state.data!.measurements.first.weightKg, 61.8);
  });

  test('风险字段缺失和非减脂目标不会发出写请求', () async {
    final api = _FakeApi();
    final controller = ProfileController(api);
    await controller.load();

    expect(
      await controller.save('risk', {'pregnant': false}),
      ProfileSaveResult.failed,
    );
    expect(controller.state.error, '请完整填写风险评估');
    expect(api.savedExpectedVersions, isEmpty);

    expect(
      await controller.save('goal', {'goalType': 'MUSCLE_GAIN'}),
      ProfileSaveResult.failed,
    );
    expect(controller.state.error, '当前目标的个性计划尚未开放');
    expect(api.savedExpectedVersions, isEmpty);
  });

  test('保存失败保留草稿', () async {
    final api = _FakeApi()..fail = true;
    final controller = ProfileController(api);
    await controller.load();
    final draft = {'workStyle': 'ACTIVE', 'sleepHours': 8};
    final result = await controller.save('lifestyle', draft);
    expect(result, ProfileSaveResult.failed);
    expect(controller.state.draft, draft);
    expect(controller.state.error, isNotNull);
  });

  test('版本冲突后刷新权威档案并保留草稿', () async {
    final api = _FakeApi()..conflict = true;
    final controller = ProfileController(api);
    await controller.load();
    final draft = {'birthDate': '1995-05-12', 'sex': 'FEMALE'};

    final result = await controller.save('basic', draft);

    expect(result, ProfileSaveResult.failed);
    expect(api.savedExpectedVersion, 7);
    expect(api.reads, 2);
    expect(controller.state.data!.profileVersion, 9);
    expect(controller.state.data!.birthDate, '1994-04-11');
    expect(controller.state.draft, draft);
    expect(controller.state.error, '健康档案已更新，请刷新后重试');
  });

  test('版本冲突重新读取完整测量历史', () async {
    final api = _FakeApi()..conflict = true;
    final controller = ProfileController(api);
    await controller.load();
    api.measurements = [
      {'id': 'm3', 'weightKg': 61.5, 'measuredAt': '2026-09-22T08:00:00Z'},
      {'id': 'm2', 'weightKg': 62, 'measuredAt': '2026-09-21T08:00:00Z'},
      ...api.measurements,
    ];

    await controller.save('basic', {'birthDate': '1995-05-12'});

    expect(controller.state.data!.measurements.map((item) => item.id), [
      'm3',
      'm2',
      'm1',
    ]);
    expect(api.measurementReads, 2);
  });

  test('保存成功后丢弃更早开始的旧档案读取', () async {
    final api = _DelayedReadApi();
    final controller = ProfileController(api);
    await controller.load();
    final stale = {
      ...api.profile,
      'basicInfo': {
        ...Map<String, dynamic>.from(api.profile['basicInfo'] as Map),
      },
    };
    api.delayedSections = Completer<Map<String, dynamic>>();

    final oldRead = controller.load();
    await Future<void>.delayed(Duration.zero);
    await controller.save('basic', {'birthDate': '1995-05-12'});
    api.delayedSections!.complete(stale);
    await oldRead;

    expect(controller.state.data!.profileVersion, 8);
    expect(controller.state.data!.birthDate, '1995-05-12');
  });
}
