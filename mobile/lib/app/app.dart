import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:healthy/app/router.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_theme.dart';
import 'package:healthy/features/hydration/application/hydration_reminder_scheduler.dart';
import 'package:healthy/features/sleep/application/sleep_reminder_scheduler.dart';
import 'package:healthy/features/tasks/application/task_notification_scheduler.dart';
import 'package:healthy/features/report/application/report_controller.dart';

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
      onLogout: () async {
        final accountKey = _session.accountKey;
        await Future.wait([
          HydrationReminderScheduler.instance
              .cancelHydrationReminders()
              .catchError((_) {}),
          SleepReminderScheduler.instance.cancelActiveAccount().catchError(
            (_) {},
          ),
          TaskNotificationScheduler.instance.cancelActiveAccount().catchError(
            (_) {},
          ),
          ReportController.clearAccountCache(accountKey).catchError((_) {}),
        ]);
      },
    );
    unawaited(
      HydrationReminderScheduler.instance.initialize().catchError((_) {}),
    );
    unawaited(SleepReminderScheduler.instance.initialize().catchError((_) {}));
    unawaited(
      TaskNotificationScheduler.instance.initialize().catchError((_) {}),
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
