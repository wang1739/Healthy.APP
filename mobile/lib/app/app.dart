import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:healthy/app/router.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';

class HealthyApp extends StatefulWidget {
  const HealthyApp({super.key});

  @override
  State<HealthyApp> createState() => _HealthyAppState();
}

class _HealthyAppState extends State<HealthyApp> {
  late final SessionController _session;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _session = SessionController(
      ApiClient.instance,
      onLogout: HydrationReminderScheduler.instance.cancelHydrationReminders,
    );
    unawaited(
      HydrationReminderScheduler.instance.initialize().catchError((_) {}),
    );
    _router = buildRouter(_session);
    _session.bootstrap();
  }

  @override
  void dispose() {
    _router.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '轻食记',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
    );
  }
}
