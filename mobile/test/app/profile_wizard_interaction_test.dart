import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/profile/presentation/profile_wizard_page.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.step = 0, this.completeness}) : super(dio: Dio());

  final int step;
  final Map<String, dynamic>? completeness;
  final savedProfiles = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> profileCompleteness() async =>
      completeness ?? {'complete': false, 'currentStep': step};

  @override
  Future<void> saveProfile(Map<String, dynamic> data) async {
    savedProfiles.add(data);
  }
}

void main() {
  testWidgets('出生日期只能通过日期选择器填写', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ProfileWizardPage(api: _FakeApiClient(), onCompleted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final birthDate = tester.widget<TextField>(find.byType(TextField).first);
    expect(birthDate.readOnly, isTrue);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('年'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
  });

  testWidgets('基础资料使用直接选择而不是下拉菜单', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ProfileWizardPage(api: _FakeApiClient(), onCompleted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('女'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('性别为其他时必须选择代谢计算依据', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ProfileWizardPage(api: _FakeApiClient(), onCompleted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('其他'));
    await tester.pump();

    expect(find.text('代谢计算依据'), findsOneWidget);
    expect(find.text('男性公式'), findsOneWidget);
    expect(find.text('女性公式'), findsOneWidget);

    await tester.tap(find.text('保存并继续'));
    await tester.pump();
    expect(find.text('请选择代谢计算依据'), findsOneWidget);
  });

  testWidgets('旧 OTHER 已完成档案回到基础资料补选后直接完成', (tester) async {
    final api = _FakeApiClient(
      completeness: {
        'complete': false,
        'currentStep': 0,
        'percentage': 99,
        'metabolicBasisRequired': true,
        'sex': 'OTHER',
        'birthDate': '1990-05-06',
      },
    );
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ProfileWizardPage(api: api, onCompleted: () => completed = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('代谢计算依据'), findsOneWidget);
    final birthDate = tester.widget<TextField>(find.byType(TextField).first);
    expect(birthDate.controller?.text, '1990-05-06');

    await tester.tap(find.text('女性公式'));
    await tester.tap(find.text('保存并继续'));
    await tester.pumpAndSettle();

    expect(api.savedProfiles.single['metabolicBasis'], 'FEMALE');
    expect(completed, isTrue);
  });

  testWidgets('身体数值使用数字键盘手动填写', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ProfileWizardPage(
          api: _FakeApiClient(step: 1),
          onCompleted: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, hasLength(3));
    expect(fields.every((field) => !field.readOnly), isTrue);
    expect(fields.every((field) => !field.stylusHandwritingEnabled), isTrue);
    expect(
      fields.every(
        (field) =>
            field.keyboardType ==
            const TextInputType.numberWithOptions(decimal: true),
      ),
      isTrue,
    );
  });
}
