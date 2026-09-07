import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({this.onLogout, super.key});

  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) => FeaturePlaceholder(
    title: '我的',
    description: '账户、健康档案、设备与隐私设置。',
    icon: Icons.person_outline,
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton(onPressed: onLogout, child: const Text('退出登录')),
    ),
  );
}
