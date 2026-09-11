import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/account/presentation/account_page.dart';

class _AccountApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> getAccount() async => {
    'phone': '13800138000',
    'maskedPhone': '138****8000',
    'displayName': '小轻',
    'status': 'ACTIVE',
    'profileComplete': true,
    'healthAuthorized': true,
  };

  @override
  Future<Map<String, dynamic>> profileCompleteness() async => {
    'currentStep': 7,
    'complete': true,
  };
}

void main() {
  testWidgets('账户中心使用已确认的分组设置结构和脱敏手机号', (tester) async {
    final session = SessionController(_AccountApi());
    await session.acceptLogin(
      const LoginResult(profileComplete: true, phone: '13800138000'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccountPage(session: session)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('138****8000'), findsOneWidget);
    expect(find.text('健康档案与账户安全'), findsOneWidget);
    expect(find.text('隐私授权'), findsOneWidget);
    expect(find.text('数据权利'), findsOneWidget);
    expect(find.text('通用设置'), findsOneWidget);
    expect(find.text('注销账户'), findsOneWidget);
    expect(find.text('13800138000'), findsNothing);
  });
}
