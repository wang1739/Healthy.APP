import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/profile/presentation/profile_overview_page.dart';

class _ProfileApi extends ApiClient {
  final saves = <String, Map<String, dynamic>>{};
  final expectedVersions = <String, int>{};
  bool needsRecalculation = false;
  String goalType = 'FAT_LOSS';

  @override
  Future<Map<String, dynamic>> profileCompleteness() async => {
    'currentStep': 7,
    'complete': true,
    'riskBlocked': false,
  };

  @override
  Future<Map<String, dynamic>> getProfileSections() async => {
    'profileVersion': 4,
    'planNeedsRecalculation': needsRecalculation,
    'basicInfo': {
      'birthDate': '1996-05-12',
      'sex': 'FEMALE',
      'metabolicBasis': 'FEMALE',
    },
    'bodyData': {'heightCm': 165},
    'lifestyle': {
      'activityLevel': 'LIGHT',
      'workStyle': 'SEDENTARY',
      'sleepHours': 7.5,
      'exerciseDays': 3,
    },
    'dietaryPreferences': {
      'dietType': 'BALANCED',
      'allergies': '花生',
      'avoidFoods': '香菜',
    },
    'healthGoal': {
      'goalType': goalType,
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

  @override
  Future<List<Map<String, dynamic>>> getProfileMeasurements() async => [
    {
      'id': 'm1',
      'weightKg': 62.5,
      'waistCm': 72,
      'bodyFatPercent': 24,
      'measuredAt': '2026-09-20T08:00:00Z',
    },
  ];

  @override
  Future<Map<String, dynamic>> saveProfileSection(
    String section,
    Map<String, dynamic> data, {
    required int expectedVersion,
  }) async {
    saves[section] = data;
    expectedVersions[section] = expectedVersion;
    needsRecalculation = section == 'basic';
    return getProfileSections();
  }

  @override
  Future<void> addMeasurement(Map<String, dynamic> data) async {
    saves['measurement'] = data;
  }
}

Future<void> _pump(WidgetTester tester, _ProfileApi api) async {
  final session = SessionController(api);
  await session.acceptLogin(const LoginResult(profileComplete: true));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: ProfileOverviewPage(session: session),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('总览固定展示六个分区并进入独立编辑页', (tester) async {
    await _pump(tester, _ProfileApi());
    for (final title in ['基本信息', '身体测量', '生活方式', '健康目标', '饮食偏好', '风险评估']) {
      expect(find.text(title), findsOneWidget);
    }

    await tester.tap(find.text('基本信息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1996-05-12'), findsOneWidget);
    expect(find.text('保存基本信息'), findsOneWidget);
    expect(find.text('当前体重'), findsNothing);
  });

  testWidgets('关键字段保存提示重算且旧计划继续显示', (tester) async {
    final api = _ProfileApi();
    await _pump(tester, api);
    await tester.tap(find.text('基本信息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final birthField = tester.widget<TextField>(find.byType(TextField));
    birthField.controller!.text = '1995-05-12';
    await tester.tap(find.text('保存基本信息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.saves.keys, ['basic']);
    expect(api.expectedVersions['basic'], 4);
    expect(find.text('计划需要重新计算'), findsWidgets);
    expect(find.textContaining('旧计划继续显示'), findsOneWidget);
  });

  testWidgets('身体测量展示历史并可新增记录', (tester) async {
    final api = _ProfileApi();
    await _pump(tester, api);
    await tester.tap(find.text('身体测量'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('62.5 千克'), findsOneWidget);
    expect(find.text('新增测量'), findsWidgets);
  });

  testWidgets('普通字段保存后明确提示成功', (tester) async {
    await _pump(tester, _ProfileApi());
    await tester.tap(find.text('生活方式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('保存生活方式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存成功'), findsWidgets);
    expect(find.textContaining('旧计划继续显示'), findsNothing);
  });

  testWidgets('健康目标明确仅开放减脂', (tester) async {
    await _pump(tester, _ProfileApi());
    await tester.tap(find.text('健康目标'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('减脂'), findsOneWidget);
    expect(find.textContaining('其他目标尚未开放'), findsOneWidget);
  });

  testWidgets('既有非减脂目标只显示中文未开放说明且不能写入', (tester) async {
    final api = _ProfileApi()..goalType = 'MUSCLE_GAIN';
    await _pump(tester, api);
    await tester.tap(find.text('健康目标'));
    await tester.pumpAndSettle();

    expect(find.text('当前目标暂未开放'), findsOneWidget);
    expect(find.textContaining('本阶段仅支持减脂目标'), findsOneWidget);
    expect(find.text('保存健康目标'), findsNothing);
    expect(api.saves, isEmpty);
  });

  testWidgets('窄屏与 1.3 倍字体无布局异常', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _ProfileApi();
    final session = SessionController(api);
    await session.acceptLogin(const LoginResult(profileComplete: true));
    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            theme: AppTheme.light,
            home: ProfileOverviewPage(session: session),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
