import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthy/app/app_shell.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/features/auth/presentation/login_page.dart';
import 'package:healthy/features/profile/presentation/profile_wizard_page.dart';
import 'package:healthy/features/account/presentation/deletion_pending_page.dart';

GoRouter buildRouter(SessionController session) => GoRouter(
  initialLocation: '/start',
  refreshListenable: session,
  redirect: (context, state) {
    final location = switch (session.stage) {
      AppStage.loading => '/start',
      AppStage.login => '/login',
      AppStage.profile => '/profile',
      AppStage.home => '/app',
      AppStage.deletionPending => '/deletion-pending',
    };
    return state.matchedLocation == location ? null : location;
  },
  routes: [
    GoRoute(path: '/start', builder: (context, state) => const _LoadingPage()),
    GoRoute(
      path: '/deletion-pending',
      builder: (context, state) => DeletionPendingPage(session: session),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => LoginPage(
        api: session.api,
        onLoggedIn: session.acceptLogin,
        onBrowse: session.skipLogin,
      ),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => ProfileWizardPage(
        api: session.api,
        onCompleted: session.completeProfile,
        onBlocked: () => session.completeProfile(blocked: true),
        onCancel: session.cancelFlow,
      ),
    ),
    GoRoute(
      path: '/app',
      builder: (context, state) => AppShell(session: session),
    ),
  ],
);

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
