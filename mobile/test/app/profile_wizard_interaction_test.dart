import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/profile/presentation/profile_wizard_page.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.step = 0}) : super(dio: Dio());

  final int step;

  @override
  Future<Map<String, dynamic>> profileCompleteness() async => {
    'complete': false,
    'currentStep': step,
  };
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
