import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/auth/presentation/login_page.dart';

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
    expect(find.text('登录并继续'), findsOneWidget);
    expect(find.text('先浏览'), findsOneWidget);

    await tester.ensureVisible(find.text('先浏览'));
    await tester.tap(find.text('先浏览'));
    expect(browsed, isTrue);
  });
}
