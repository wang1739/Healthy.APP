import 'package:go_router/go_router.dart';
import 'package:healthy/app/app_shell.dart';

final appRouter = GoRouter(
  routes: [GoRoute(path: '/', builder: (context, state) => const AppShell())],
);
