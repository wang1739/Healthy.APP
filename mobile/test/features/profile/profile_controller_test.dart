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
    profile = {
      ...profile,
      'profileVersion': expectedVersion + 1,
      'planNeedsRecalculation': section == 'basic',
    };
    return profile;
  }

  @override
  Future<List<Map<String, dynamic>>> getProfileMeasurements() async => [
    {'id': 'm1', 'weightKg': 62.5, 'measuredAt': '2026-09-20T08:00:00Z'},
  ];
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
}
