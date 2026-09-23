import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    this.restored,
    this.currentStep = 0,
    this.profileComplete = false,
    this.riskBlocked = false,
    this.failLogout = false,
  });

  final LoginResult? restored;
  int currentStep;
  bool profileComplete;
  bool riskBlocked;
  final bool failLogout;
  bool loggedOut = false;

  @override
  Future<LoginResult?> restoreSession() async => restored;

  @override
  Future<Map<String, dynamic>> profileCompleteness() async => {
    'currentStep': currentStep,
    'complete': profileComplete,
    'riskBlocked': riskBlocked,
  };

  @override
  Future<void> logout({bool allDevices = false}) async {
    loggedOut = true;
    if (failLogout) throw StateError('会话已撤销');
  }
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

  test('注销处理中登录只进入恢复页面', () async {
    final session = SessionController(_FakeApiClient());

    await session.acceptLogin(
      const LoginResult(
        profileComplete: true,
        phone: '13800138000',
        accountStatus: 'DELETION_PENDING',
      ),
    );

    expect(session.stage, AppStage.deletionPending);
    expect(session.access, UserAccess.profileIncomplete);
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

  test('服务端会话已撤销时仍完成本地退出', () async {
    final session = SessionController(
      _FakeApiClient(failLogout: true),
      onHealthDataCleared: () async {},
    );
    await session.acceptLogin(
      const LoginResult(profileComplete: true, phone: '13800138000'),
    );

    await session.logout();

    expect(session.stage, AppStage.home);
    expect(session.access, UserAccess.guest);
  });

  test('健康数据变化和注销申请都会立即触发本地健康状态清理', () async {
    var cleared = 0;
    final api = _FakeApiClient();
    final session = SessionController(
      api,
      onHealthDataCleared: () async => cleared++,
    );
    await session.acceptLogin(
      const LoginResult(profileComplete: true, phone: '13800138000'),
    );
    final revision = session.sessionRevision;

    await session.healthDataChanged(healthAuthorized: false);

    expect(cleared, 1);
    expect(session.healthAuthorized, isFalse);
    expect(session.sessionRevision, revision + 1);

    await session.accountDeletionRequested();

    expect(cleared, 2);
    expect(session.accountKey, 'guest');
    expect(session.phone, isNull);
  });

  test('刷新档案状态时完整账号可以降级为未完成', () async {
    final api = _FakeApiClient(
      currentStep: 7,
      profileComplete: true,
      riskBlocked: true,
    );
    final session = SessionController(api);
    await session.acceptLogin(
      const LoginResult(profileComplete: true, phone: '13800138000'),
    );
    expect(session.access, UserAccess.profileComplete);

    api
      ..currentStep = 0
      ..profileComplete = false
      ..riskBlocked = false;
    await session.refreshProfileState();

    expect(session.access, UserAccess.profileIncomplete);
    expect(session.profileStep, 0);
    expect(session.riskBlocked, isFalse);
  });

  test('删除档案后降级并清空档案状态但保留账号与授权', () async {
    final api = _FakeApiClient(currentStep: 7, profileComplete: true);
    var cleared = 0;
    final session = SessionController(
      api,
      onHealthDataCleared: () async => cleared++,
    );
    await session.acceptLogin(
      const LoginResult(profileComplete: true, phone: '13800138000'),
    );
    final accountKey = session.accountKey;
    final revision = session.sessionRevision;
    var notifications = 0;
    session.addListener(() => notifications++);

    await session.healthDataChanged(profileDeleted: true);

    expect(cleared, 1);
    expect(session.access, UserAccess.profileIncomplete);
    expect(session.profileStep, 0);
    expect(session.riskBlocked, isFalse);
    expect(session.stage, AppStage.profile);
    expect(session.healthAuthorized, isTrue);
    expect(session.phone, '13800138000');
    expect(session.accountKey, accountKey);
    expect(session.sessionRevision, revision + 1);
    expect(notifications, 1);
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

  test('游客登录为未建档账号后可直接恢复创建个人任务', () async {
    final session = SessionController(_FakeApiClient(currentStep: 2));
    session.startRestrictedFlow(label: '创建任务', destination: 0);

    await session.acceptLogin(
      const LoginResult(profileComplete: false, phone: '13800138000'),
    );

    expect(session.access, UserAccess.profileIncomplete);
    expect(session.stage, AppStage.home);
    expect(session.pendingFeature?.label, '创建任务');
  });
}
