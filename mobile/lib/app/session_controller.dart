import 'package:flutter/foundation.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppStage { loading, login, home, profile }

enum UserAccess { guest, profileIncomplete, profileComplete }

class PendingFeature {
  const PendingFeature({required this.label, required this.destination});

  final String label;
  final int destination;
}

class SessionController extends ChangeNotifier {
  SessionController(this.api, {this.onLogout});

  static const _guestBrowseKey = 'guest_browse_enabled';

  final ApiClient api;
  final Future<void> Function()? onLogout;
  AppStage stage = AppStage.loading;
  UserAccess access = UserAccess.guest;
  int profileStep = 0;
  bool riskBlocked = false;
  int sessionRevision = 0;
  PendingFeature? _pendingFeature;

  PendingFeature? get pendingFeature => _pendingFeature;

  Future<void> bootstrap() async {
    try {
      final session = await api.restoreSession();
      if (session != null) {
        access = session.profileComplete
            ? UserAccess.profileComplete
            : UserAccess.profileIncomplete;
        await _loadProfileState();
        stage = AppStage.home;
      } else {
        access = UserAccess.guest;
        final preferences = await SharedPreferences.getInstance();
        stage = preferences.getBool(_guestBrowseKey) == true
            ? AppStage.home
            : AppStage.login;
      }
    } catch (_) {
      access = UserAccess.guest;
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
    _pendingFeature = null;
    stage = AppStage.home;
    notifyListeners();
  }

  Future<void> acceptLogin(LoginResult result) async {
    sessionRevision++;
    access = result.profileComplete
        ? UserAccess.profileComplete
        : UserAccess.profileIncomplete;
    await _loadProfileState();
    stage = access == UserAccess.profileIncomplete
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
    if (blocked) {
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
      await onLogout?.call();
    } catch (_) {
      // Local notification cleanup must not trap the user in a session.
    }
    await api.logout();
    sessionRevision++;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_guestBrowseKey, true);
    access = UserAccess.guest;
    profileStep = 0;
    riskBlocked = false;
    _pendingFeature = null;
    stage = AppStage.home;
    notifyListeners();
  }

  Future<void> _loadProfileState() async {
    try {
      final data = await api.profileCompleteness();
      profileStep = ((data['currentStep'] as num?)?.toInt() ?? 0).clamp(0, 7);
      riskBlocked = data['riskBlocked'] == true;
      if (data['complete'] == true) access = UserAccess.profileComplete;
    } catch (_) {
      profileStep = access == UserAccess.profileComplete ? 7 : 0;
    }
  }
}
