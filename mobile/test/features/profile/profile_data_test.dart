import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/features/profile/domain/profile_data.dart';

void main() {
  test('解析六分区和身体测量历史', () {
    final profile = ProfileData.fromJson({
      'profileVersion': 7,
      'planNeedsRecalculation': true,
      'sections': {
        'basic': {
          'birthDate': '1996-05-12',
          'sex': 'FEMALE',
          'metabolicBasis': 'FEMALE',
        },
        'body': {
          'heightCm': 165,
          'measurements': [
            {
              'id': 'm1',
              'weightKg': 62.5,
              'waistCm': 72,
              'bodyFatPercent': 24,
              'measuredAt': '2026-09-20T08:00:00Z',
            },
          ],
        },
        'lifestyle': {
          'activityLevel': 'LIGHT',
          'workStyle': 'SEDENTARY',
          'sleepHours': 7.5,
          'exerciseDays': 3,
        },
        'preferences': {
          'dietType': 'BALANCED',
          'allergies': '花生、海鲜',
          'avoidFoods': '香菜',
        },
        'goal': {
          'goalType': 'FAT_LOSS',
          'targetWeightKg': 58,
          'targetDate': '2027-01-20',
        },
        'risk': {
          'pregnant': false,
          'breastfeeding': false,
          'eatingDisorderRisk': false,
          'seriousChronicDisease': false,
          'unsafeTarget': false,
          'riskBlocked': false,
        },
      },
    });

    expect(profile.planNeedsRecalculation, isTrue);
    expect(profile.profileVersion, 7);
    expect(profile.birthDate, '1996-05-12');
    expect(profile.heightCm, 165);
    expect(profile.measurements.single.weightKg, 62.5);
    expect(profile.allergies, ['花生', '海鲜']);
    expect(profile.goalType, 'FAT_LOSS');
  });

  test('兼容服务端下划线字段且缺失枚举不伪造真实值', () {
    final profile = ProfileData.fromJson({
      'birth_date': '1990-01-01',
      'height_cm': 180,
      'activity_level': 'MODERATE',
      'plan_needs_recalculation': false,
    });

    expect(profile.birthDate, '1990-01-01');
    expect(profile.heightCm, 180);
    expect(profile.activityLevel, 'MODERATE');
    expect(profile.sex, isEmpty);
    expect(profile.workStyle, isEmpty);
    expect(profile.sleepHours, isNull);
    expect(profile.exerciseDays, isNull);
    expect(profile.dietType, isEmpty);
    expect(profile.measurements, isEmpty);
  });

  test('未知枚举原样解析并交给编辑页要求用户明确选择', () {
    final profile = ProfileData.fromJson({
      'basicInfo': {'sex': 'UNKNOWN_SEX'},
      'lifestyle': {
        'activityLevel': 'EXTREME',
        'workStyle': 'REMOTE',
        'exerciseDays': 9,
      },
      'dietaryPreferences': {'dietType': 'KETO'},
    });

    expect(profile.sex, 'UNKNOWN_SEX');
    expect(profile.activityLevel, 'EXTREME');
    expect(profile.workStyle, 'REMOTE');
    expect(profile.exerciseDays, 9);
    expect(profile.dietType, 'KETO');
  });

  test('解析分区接口的真实字段结构', () {
    final profile = ProfileData.fromJson({
      'basicInfo': {
        'birthDate': '1990-01-01',
        'sex': 'MALE',
        'metabolicBasis': 'MALE',
      },
      'bodyData': {
        'heightCm': 178,
        'latestMeasurement': {
          'id': 'm2',
          'weightKg': 72,
          'measuredAt': '2026-09-22T08:00:00Z',
        },
      },
      'lifestyle': {'activityLevel': 'HIGH'},
      'dietaryPreferences': {'dietType': 'LOW_CARB', 'allergies': '花生'},
      'healthGoal': {'goalType': 'FAT_LOSS', 'targetWeightKg': 70},
      'riskInfo': {
        'pregnant': false,
        'breastfeeding': false,
        'eatingDisorderRisk': false,
        'seriousChronicDisease': true,
        'unsafeTarget': false,
        'riskBlocked': true,
      },
      'planNeedsRecalculation': true,
      'profileVersion': 11,
    });

    expect(profile.sex, 'MALE');
    expect(profile.heightCm, 178);
    expect(profile.dietType, 'LOW_CARB');
    expect(profile.targetWeightKg, 70);
    expect(profile.riskBlocked, isTrue);
    expect(profile.seriousChronicDisease, isTrue);
    expect(profile.measurements.single.id, 'm2');
    expect(profile.profileVersion, 11);
  });
}
