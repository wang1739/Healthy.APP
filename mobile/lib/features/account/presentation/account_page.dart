import 'package:flutter/material.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    title: '我的',
    description: '账户、健康档案、会员与隐私设置。',
    icon: Icons.person_outline,
  );
}
