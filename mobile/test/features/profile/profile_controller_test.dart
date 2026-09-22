import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/profile/application/profile_controller.dart';

class _FakeApi extends ApiClient {
  Map<String, dynamic> profile = {
    'planNeedsRecalculation': false,
    'sections': {
      'basic': {'birthDate': '1996-05-12', 'sex': 'FEMALE'},
      'body': {'heightCm': 165},
      'lifestyle': {
        'activityLevel': 'LIGHT',
        'workStyle': 'SEDENTARY',
        'sleepHours': 7.5,
        'exerciseDays': 3,
      },
      'preferences': {
        'dietType': 'BALANCED',
        'allergies': '',
        'avoidFoods': '',
      },
      'goal': {
        'goalType': 'FAT_LOSS',
        'targetWeightKg': 58,
        'targetDate': '2027-01-20',
      },
      'risk': {'riskBlocked': false},
    },
  };
  String? savedSection;
  Map<String, dynamic>? savedBody;
  bool fail = false;

  @override
  Future<Map<String, dynamic>> getProfileSections() async => profile;

  @override
  Future<Map<String, dynamic>> saveProfileSection(
    String section,
    Map<String, dynamic> data,
  ) async {
    savedSection = section;
    savedBody = data;
    if (fail) throw DioException(requestOptions: RequestOptions());
    profile = {...profile, 'planNeedsRecalculation': section == 'basic'};
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
}
