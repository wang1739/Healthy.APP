import 'package:flutter/material.dart';
import 'package:healthy/app/router.dart';
import 'package:healthy/core/theme/app_theme.dart';

class HealthyApp extends StatelessWidget {
  const HealthyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '轻食记',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
