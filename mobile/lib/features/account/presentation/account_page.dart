import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/account/presentation/account_detail_pages.dart';
import 'package:healthy/features/profile/presentation/profile_overview_page.dart';
import 'package:healthy/shared/widgets/feature_placeholder.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({required this.session, super.key});
  final SessionController session;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Map<String, dynamic>? account;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.session.access != UserAccess.guest) _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.session.api.getAccount();
      if (mounted) {
        setState(() {
          account = value;
          error = null;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = ApiClient.errorMessage(exception));
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.access == UserAccess.guest) {
      return FeaturePlaceholder(
        title: '我的',
        description: '账户、健康档案、设备与隐私设置。',
        icon: Icons.person_outline,
        showFrameworkNotice: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('游客模式', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('登录后可保存健康数据并管理个人信息。'),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: widget.session.openLogin,
              child: const Text('登录并开启个性化服务'),
            ),
          ],
        ),
      );
    }

    if (account == null) {
      return FeaturePlaceholder(
        title: '我的',
        description: '账户、健康档案、设备与隐私设置。',
        icon: Icons.person_outline,
        showFrameworkNotice: false,
        child: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text(error!),
        ),
      );
    }

    final theme = Theme.of(context);
    final phone = account!['phone']?.toString() ?? '';
    return FeaturePlaceholder(
      title: '我的',
      description: '账户、健康档案、设备与隐私设置。',
      icon: Icons.person_outline,
      showFrameworkNotice: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account!['displayName']?.toString() ?? '轻食记用户',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(account!['maskedPhone']?.toString() ?? '手机号未显示'),
                const SizedBox(height: 8),
                Text(
                  account!['profileComplete'] == true ? '健康档案已完成' : '健康档案待完善',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Group(
            title: '健康档案与账户安全',
            children: [
              _Item(
                icon: Icons.assignment_ind_outlined,
                title: '健康档案',
                subtitle: account!['profileComplete'] == true
                    ? '分区查看与编辑'
                    : '继续完成建档',
                onTap: account!['profileComplete'] == true
                    ? () => _open(ProfileOverviewPage(session: widget.session))
                    : widget.session.openProfile,
              ),
              _Item(
                icon: Icons.devices_outlined,
                title: '设备管理',
                subtitle: '查看和移除登录设备',
                onTap: () => _open(
                  DeviceManagementPage(api: widget.session.api, phone: phone),
                ),
              ),
              _Item(
                icon: Icons.phone_iphone_outlined,
                title: '更换手机号',
                subtitle: '需要新旧手机号双重验证',
                onTap: () => _open(
                  PhoneChangePage(api: widget.session.api, oldPhone: phone),
                ),
              ),
              _Item(
                icon: Icons.shield_outlined,
                title: '安全记录',
                subtitle: '查看近期账户安全操作',
                onTap: () => _open(SecurityEventsPage(api: widget.session.api)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            title: '隐私授权',
            children: [
              _Item(
                icon: Icons.privacy_tip_outlined,
                title: '隐私中心',
                subtitle: account!['healthAuthorized'] == true
                    ? '健康数据已授权'
                    : '健康数据授权未开启',
                onTap: () => _open(PrivacyCenterPage(api: widget.session.api)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            title: '数据权利',
            children: [
              _Item(
                icon: Icons.file_download_outlined,
                title: '导出与删除数据',
                subtitle: '导出中文 PDF 或永久删除健康数据',
                onTap: () => _open(
                  DataRightsPage(api: widget.session.api, phone: phone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            title: '通用设置',
            children: [
              _Item(
                icon: Icons.logout,
                title: '退出登录',
                onTap: widget.session.logout,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            title: '账户操作',
            children: [
              _Item(
                icon: Icons.delete_forever_outlined,
                title: '注销账户',
                subtitle: '申请后进入 7 天冷静期',
                danger: true,
                onTap: () => _open(
                  AccountDeletionPage(session: widget.session, phone: phone),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge),
      ),
      Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: children),
      ),
    ],
  );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
