import 'package:flutter/foundation.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppStage { loading, login, home, profile, deletionPending }

enum UserAccess { guest, profileIncomplete, profileComplete }

class PendingFeature {
  const PendingFeature({required this.label, required this.destination});

  final String label;
  final int destination;
}

class SessionController extends ChangeNotifier {
  SessionController(this.api, {this.onLogout, this.onHealthDataCleared});

  static const _guestBrowseKey = 'guest_browse_enabled';

  final ApiClient api;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onHealthDataCleared;
  AppStage stage = AppStage.loading;
  UserAccess access = UserAccess.guest;
  int profileStep = 0;
  bool riskBlocked = false;
  bool healthAuthorized = true;
  int sessionRevision = 0;
  String accountKey = 'guest';
  String? phone;
  PendingFeature? _pendingFeature;

  PendingFeature? get pendingFeature => _pendingFeature;

  Future<void> bootstrap() async {
    try {
      final session = await api.restoreSession();
      if (session != null) {
        phone = session.phone;
        if (session.accountStatus == 'DELETION_PENDING') {
          access = UserAccess.profileIncomplete;
          stage = AppStage.deletionPending;
          notifyListeners();
          return;
        }
        accountKey = _accountKey(session.phone);
        access = session.profileComplete
            ? UserAccess.profileComplete
            : UserAccess.profileIncomplete;
        await _loadProfileState();
        stage = AppStage.home;
      } else {
        access = UserAccess.guest;
        accountKey = 'guest';
        final preferences = await SharedPreferences.getInstance();
        stage = preferences.getBool(_guestBrowseKey) == true
            ? AppStage.home
            : AppStage.login;
      }
    } catch (_) {
      access = UserAccess.guest;
      accountKey = 'guest';
      final preferences = await SharedPreferences.getInstance();
      stage = preferences.getBool(_guestBrowseKey) == true
          ? AppStage.home
          : AppStage.login;
    }
    notifyListeners();
  }

  Future<void> skipLogin() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_guestBrowseKey, true);
    access = UserAccess.guest;
    accountKey = 'guest';
    healthAuthorized = true;
    _pendingFeature = null;
    stage = AppStage.home;
    notifyListeners();
  }

  Future<void> acceptLogin(LoginResult result) async {
    sessionRevision++;
    healthAuthorized = true;
    phone = result.phone;
    if (result.accountStatus == 'DELETION_PENDING') {
      access = UserAccess.profileIncomplete;
      accountKey = _accountKey(result.phone);
      stage = AppStage.deletionPending;
      notifyListeners();
      return;
    }
    accountKey = _accountKey(result.phone);
    access = result.profileComplete
        ? UserAccess.profileComplete
        : UserAccess.profileIncomplete;
    await _loadProfileState();
    final personalTaskFlow =
        _pendingFeature?.label == '创建任务' || _pendingFeature?.label == '查看每日任务';
    stage = access == UserAccess.profileIncomplete && !personalTaskFlow
        ? AppStage.profile
        : AppStage.home;
    notifyListeners();
  }

  bool startRestrictedFlow({required String label, required int destination}) {
    if (access == UserAccess.profileComplete) return true;
    _pendingFeature = PendingFeature(label: label, destination: destination);
    stage = access == UserAccess.guest ? AppStage.login : AppStage.profile;
    notifyListeners();
    return false;
  }

  void openLogin() {
    _pendingFeature = null;
    stage = AppStage.login;
    notifyListeners();
  }

  void openProfile() {
    if (access == UserAccess.guest) {
      openLogin();
      return;
    }
    _pendingFeature = null;
    stage = AppStage.profile;
    notifyListeners();
  }

  void cancelFlow() {
    _pendingFeature = null;
    stage = AppStage.home;
    notifyListeners();
  }

  void completeProfile({bool blocked = false}) {
    sessionRevision++;
    access = UserAccess.profileComplete;
    profileStep = 7;
    riskBlocked = blocked;
    if (blocked && _pendingFeature?.destination != 3) {
      _pendingFeature = null;
    } else {
      _pendingFeature ??= const PendingFeature(label: '查看减脂方案', destination: 2);
    }
    stage = AppStage.home;
    notifyListeners();
  }

  PendingFeature? consumePendingFeature() {
    final feature = _pendingFeature;
    _pendingFeature = null;
    return feature;
  }

  Future<void> logout() async {
    try {
      await (onHealthDataCleared ?? onLogout)?.call();
    } catch (_) {
      // Local notification cleanup must not trap the user in a session.
    }
    try {
      await api.logout();
    } catch (_) {
      // Local logout must complete even when the session is already revoked.
    }
    sessionRevision++;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_guestBrowseKey, true);
    access = UserAccess.guest;
    accountKey = 'guest';
    phone = null;
    profileStep = 0;
    riskBlocked = false;
    healthAuthorized = true;
    _pendingFeature = null;
    stage = AppStage.home;
    notifyListeners();
  }

  Future<void> accountDeletionRequested() async {
    try {
      await (onHealthDataCleared ?? onLogout)?.call();
    } catch (_) {
      // Server-side deletion still ends the session if local cleanup fails.
    }
    try {
      await api.logout();
    } catch (_) {
      // Account deletion revokes the token before this best-effort logout.
    }
    sessionRevision++;
    access = UserAccess.guest;
    accountKey = 'guest';
    phone = null;
    profileStep = 0;
    riskBlocked = false;
    healthAuthorized = true;
    _pendingFeature = null;
    stage = AppStage.login;
    notifyListeners();
  }

  Future<void> healthDataChanged({
    bool? healthAuthorized,
    bool profileDeleted = false,
  }) async {
    try {
      await (onHealthDataCleared ?? onLogout)?.call();
    } catch (_) {
      // The server result remains authoritative when local cleanup is partial.
    }
    if (healthAuthorized != null) this.healthAuthorized = healthAuthorized;
    if (profileDeleted && access != UserAccess.guest) {
      access = UserAccess.profileIncomplete;
      profileStep = 0;
      riskBlocked = false;
      _pendingFeature = null;
      stage = AppStage.profile;
    }
    sessionRevision++;
    notifyListeners();
  }

  Future<void> accountRecovered() async {
    sessionRevision++;
    final account = await api.getAccount();
    phone = account['phone'] as String?;
    accountKey = _accountKey(phone);
    access = account['profileComplete'] == true
        ? UserAccess.profileComplete
        : UserAccess.profileIncomplete;
    await _loadProfileState();
    stage = AppStage.home;
    notifyListeners();
  }

  Future<void> refreshProfileState() async {
    await _loadProfileState();
    notifyListeners();
  }

  Future<void> _loadProfileState() async {
    try {
      final data = await api.profileCompleteness();
      profileStep = ((data['currentStep'] as num?)?.toInt() ?? 0).clamp(0, 7);
      riskBlocked = data['riskBlocked'] == true;
      if (access != UserAccess.guest) {
        access = data['complete'] == true
            ? UserAccess.profileComplete
            : UserAccess.profileIncomplete;
      }
    } catch (_) {
      profileStep = access == UserAccess.profileComplete ? 7 : 0;
    }
  }

  String _accountKey(String? phone) {
    final value = phone?.trim();
    if (value == null || value.isEmpty) return 'account';
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
