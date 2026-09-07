import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({required this.session, super.key});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final child = switch (session.access) {
      UserAccess.guest => _GuestActions(onLogin: session.openLogin),
      UserAccess.profileIncomplete => _ProfileActions(
        step: session.profileStep,
        onProfile: session.openProfile,
        onLogout: session.logout,
      ),
      UserAccess.profileComplete => _CompletedActions(
        riskBlocked: session.riskBlocked,
        onLogout: session.logout,
      ),
    };
    return FeaturePlaceholder(
      title: '我的',
      description: '账户、健康档案、设备与隐私设置。',
      icon: Icons.person_outline,
      child: child,
    );
  }
}

class _GuestActions extends StatelessWidget {
  const _GuestActions({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('游客模式', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      const Text('登录后可保存健康数据并获得个性化计划。'),
      const SizedBox(height: 18),
      FilledButton(onPressed: onLogin, child: const Text('登录并开启个性化服务')),
    ],
  );
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.step,
    required this.onProfile,
    required this.onLogout,
  });

  final int step;
  final VoidCallback onProfile;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('账号已登录', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text('健康档案 $step/7'),
      const SizedBox(height: 18),
      FilledButton(onPressed: onProfile, child: const Text('继续完善健康档案')),
      const SizedBox(height: 8),
      TextButton(onPressed: onLogout, child: const Text('退出登录')),
    ],
  );
}

class _CompletedActions extends StatelessWidget {
  const _CompletedActions({required this.riskBlocked, required this.onLogout});

  final bool riskBlocked;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('健康档案已完成', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(riskBlocked ? '部分自动计划已根据风险评估暂停。' : '个性化健康功能已经开放。'),
      const SizedBox(height: 18),
      OutlinedButton(onPressed: onLogout, child: const Text('退出登录')),
    ],
  );
}
