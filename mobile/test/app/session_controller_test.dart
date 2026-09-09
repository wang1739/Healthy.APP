import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.restored, this.currentStep = 0});

  final LoginResult? restored;
  final int currentStep;
  bool loggedOut = false;

  @override
  Future<LoginResult?> restoreSession() async => restored;

  @override
  Future<Map<String, dynamic>> profileCompleteness() async => {
    'currentStep': currentStep,
    'complete': false,
  };

  @override
  Future<void> logout({bool allDevices = false}) async => loggedOut = true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('首次无会话时进入登录页', () async {
    final session = SessionController(_FakeApiClient());

    await session.bootstrap();

    expect(session.stage, AppStage.login);
    expect(session.access, UserAccess.guest);
  });

  test('选择先浏览后会记住游客偏好', () async {
    final session = SessionController(_FakeApiClient());

    await session.skipLogin();

    expect(session.stage, AppStage.home);
    expect(session.access, UserAccess.guest);
    expect(
      (await SharedPreferences.getInstance()).getBool('guest_browse_enabled'),
      isTrue,
    );

    final nextLaunch = SessionController(_FakeApiClient());
    await nextLaunch.bootstrap();
    expect(nextLaunch.stage, AppStage.home);
  });

  test('普通登录未建档时进入健康档案', () async {
    final session = SessionController(_FakeApiClient(currentStep: 3));

    await session.acceptLogin(const LoginResult(profileComplete: false));

    expect(session.stage, AppStage.profile);
    expect(session.access, UserAccess.profileIncomplete);
    expect(session.profileStep, 3);
  });

  test('受限功能会连续进入登录和建档并返回原功能', () async {
    final session = SessionController(_FakeApiClient(currentStep: 2));

    session.startRestrictedFlow(label: '记录饮食', destination: 1);
    expect(session.stage, AppStage.login);

    await session.acceptLogin(const LoginResult(profileComplete: false));
    expect(session.stage, AppStage.profile);

    session.completeProfile();
    expect(session.stage, AppStage.home);
    expect(session.access, UserAccess.profileComplete);
    expect(session.consumePendingFeature()?.label, '记录饮食');
    expect(session.consumePendingFeature(), isNull);
  });

  test('退出登录后回到游客首页', () async {
    final api = _FakeApiClient(
      restored: const LoginResult(profileComplete: true),
    );
    final session = SessionController(api);
    await session.bootstrap();

    await session.logout();

    expect(api.loggedOut, isTrue);
    expect(session.stage, AppStage.home);
    expect(session.access, UserAccess.guest);
  });

  test('直接完成健康档案后进入计划预览', () {
    final session = SessionController(_FakeApiClient());

    session.completeProfile();

    expect(session.pendingFeature?.destination, 2);
    expect(session.pendingFeature?.label, '查看减脂方案');
  });

  test('睡眠提醒使用稳定且不暴露手机号的账号键', () async {
    const phone = '13800138000';
    final first = SessionController(
      _FakeApiClient(
        restored: const LoginResult(profileComplete: true, phone: phone),
      ),
    );
    final second = SessionController(
      _FakeApiClient(
        restored: const LoginResult(profileComplete: true, phone: phone),
      ),
    );
    final other = SessionController(
      _FakeApiClient(
        restored: const LoginResult(
          profileComplete: true,
          phone: '13900139000',
        ),
      ),
    );
    await Future.wait([
      first.bootstrap(),
      second.bootstrap(),
      other.bootstrap(),
    ]);

    expect(first.accountKey, second.accountKey);
    expect(first.accountKey, isNot(other.accountKey));
    expect(first.accountKey, isNot(contains(phone)));
  });
}
