import 'package:flutter/foundation.dart';
import 'package:healthy/core/api/api_client.dart';

enum AppStage { loading, login, profile, home }

class SessionController extends ChangeNotifier {
  SessionController(this.api);

  final ApiClient api;
  AppStage stage = AppStage.loading;

  Future<void> bootstrap() async {
    try {
      final session = await api.restoreSession();
      stage = session == null
          ? AppStage.login
          : session.profileComplete
          ? AppStage.home
          : AppStage.profile;
    } catch (_) {
      stage = AppStage.login;
    }
    notifyListeners();
  }

  void acceptLogin(LoginResult result) {
    stage = result.profileComplete ? AppStage.home : AppStage.profile;
    notifyListeners();
  }

  void completeProfile() {
    stage = AppStage.home;
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
    stage = AppStage.login;
    notifyListeners();
  }
}
