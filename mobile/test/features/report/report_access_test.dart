import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('报告意图使用现有登录和建档回跳闭环', () async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(_NoopApi());
    await session.skipLogin();
    expect(
      session.startRestrictedFlow(label: '生成健康报告', destination: 3),
      isFalse,
    );
    expect(session.stage, AppStage.login);
    expect(session.pendingFeature?.destination, 3);
  });

  test('风险建档完成后仍恢复报告原意图', () async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(_NoopApi());
    session.startRestrictedFlow(label: '生成健康报告', destination: 3);
    await session.acceptLogin(const LoginResult(profileComplete: false));

    session.completeProfile(blocked: true);

    expect(session.access, UserAccess.profileComplete);
    expect(session.consumePendingFeature()?.destination, 3);
  });
}

class _NoopApi extends ApiClient {}
