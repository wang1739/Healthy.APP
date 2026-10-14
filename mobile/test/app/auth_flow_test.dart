import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/auth/presentation/login_page.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.healthAuthorized});

  final bool healthAuthorized;
  int loginCalls = 0;
  int consentCalls = 0;

  @override
  Future<LoginResult> smsLogin({
    required String phone,
    required String code,
    required String deviceName,
    String? password,
  }) async {
    loginCalls++;
    return LoginResult(profileComplete: false, phone: phone);
  }

  @override
  Future<Map<String, dynamic>> getPrivacy() async => {
    'healthAuthorized': healthAuthorized,
    'latestDocuments': [
      {
        'type': 'HEALTH_DATA_AUTHORIZATION',
        'version': '2026-09',
        'effectiveAt': '2026-09-01T00:00:00Z',
      },
    ],
  };

  @override
  Future<void> acceptConsent(String type, String version) async {
    expect(type, 'HEALTH_DATA_AUTHORIZATION');
    expect(version, '2026-09');
    consentCalls++;
  }
}

Future<void> _fillLogin(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), '13800138000');
  await tester.enterText(find.byType(TextField).at(1), '123456');
}

Future<void> _acceptBoth(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox).at(0));
  await tester.pump();
  await tester.tap(find.byType(Checkbox).at(1));
  await tester.pump();
}

Future<void> _submitLogin(WidgetTester tester) async {
  final button = find.text('登录并继续');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  testWidgets('shows the Chinese login flow and consent boundary', (
    tester,
  ) async {
    var browsed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          api: ApiClient(dio: Dio()),
          onLoggedIn: (_) {},
          onBrowse: () => browsed = true,
        ),
      ),
    );

    expect(find.text('欢迎来到轻食记'), findsOneWidget);
    expect(find.text('验证码登录'), findsOneWidget);
    expect(find.text('密码登录'), findsOneWidget);
    expect(find.textContaining('用户协议'), findsOneWidget);
    expect(find.textContaining('健康数据授权说明'), findsOneWidget);
    expect(find.text('登录并继续'), findsOneWidget);
    expect(find.text('先浏览'), findsOneWidget);

    await tester.ensureVisible(find.text('先浏览'));
    await tester.tap(find.text('先浏览'));
    expect(browsed, isTrue);
  });

  testWidgets('健康数据授权必须独立勾选', (tester) async {
    final api = _FakeApiClient(healthAuthorized: false);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(api: api, onLoggedIn: (_) {}, onBrowse: () {}),
      ),
    );
    await _fillLogin(tester);
    await tester.tap(find.byType(Checkbox).first);
    await _submitLogin(tester);

    expect(find.text('请先同意健康数据授权说明'), findsOneWidget);
    expect(api.loginCalls, 0);
  });

  testWidgets('登录后为未授权账号提交最新健康授权再继续', (tester) async {
    final api = _FakeApiClient(healthAuthorized: false);
    var loggedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          api: api,
          onLoggedIn: (_) => loggedIn = true,
          onBrowse: () {},
        ),
      ),
    );
    await _fillLogin(tester);
    await _acceptBoth(tester);
    await _submitLogin(tester);
    await tester.pumpAndSettle();

    expect(api.loginCalls, 1);
    expect(api.consentCalls, 1);
    expect(loggedIn, isTrue);
  });

  testWidgets('已授权账号登录时不重复提交授权记录', (tester) async {
    final api = _FakeApiClient(healthAuthorized: true);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(api: api, onLoggedIn: (_) {}, onBrowse: () {}),
      ),
    );
    await _fillLogin(tester);
    await _acceptBoth(tester);
    await _submitLogin(tester);
    await tester.pumpAndSettle();

    expect(api.loginCalls, 1);
    expect(api.consentCalls, 0);
  });
}
