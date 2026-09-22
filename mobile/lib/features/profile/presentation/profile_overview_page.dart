import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/theme/app_spacing.dart';
import 'package:healthy/features/profile/application/profile_controller.dart';
import 'package:healthy/features/profile/domain/profile_data.dart';
import 'package:healthy/features/profile/presentation/profile_section_page.dart';
import 'package:healthy/features/plan/application/plan_controller.dart';

class ProfileOverviewPage extends ConsumerStatefulWidget {
  const ProfileOverviewPage({required this.session, super.key});
  final SessionController session;

  @override
  ConsumerState<ProfileOverviewPage> createState() =>
      _ProfileOverviewPageState();
}

class _ProfileOverviewPageState extends ConsumerState<ProfileOverviewPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(profileControllerProvider(widget.session.api)).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(profileControllerProvider(widget.session.api));
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('健康档案')),
      body: state.data == null
          ? Center(
              child: state.error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: controller.load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
            )
          : RefreshIndicator(
              onRefresh: controller.load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.page),
                children: [
                  if (state.data!.planNeedsRecalculation) ...[
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: const ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('计划需要重新计算'),
                        subtitle: Text('旧计划和历史仍会保留，确认新计划后才会切换。'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.small),
                  ],
                  ...ProfileSection.values.map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.small),
                      child: Card(
                        child: ListTile(
                          leading: Icon(_icon(section)),
                          title: Text(section.title),
                          subtitle: Text(_subtitle(section)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(section, controller),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _open(
    ProfileSection section,
    ProfileController controller,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ProfileSectionPage(section: section, controller: controller),
      ),
    );
    await controller.load();
    await widget.session.refreshProfileState();
    if (!widget.session.riskBlocked) {
      await ref.read(planControllerProvider(widget.session.api)).load();
    }
  }

  IconData _icon(ProfileSection section) => switch (section) {
    ProfileSection.basic => Icons.badge_outlined,
    ProfileSection.body => Icons.monitor_weight_outlined,
    ProfileSection.lifestyle => Icons.directions_walk_outlined,
    ProfileSection.goal => Icons.flag_outlined,
    ProfileSection.preferences => Icons.restaurant_menu_outlined,
    ProfileSection.risk => Icons.health_and_safety_outlined,
  };

  String _subtitle(ProfileSection section) => switch (section) {
    ProfileSection.basic => '出生日期、性别与代谢计算依据',
    ProfileSection.body => '身高、当前体重与测量历史',
    ProfileSection.lifestyle => '活动、工作、睡眠与运动',
    ProfileSection.goal => '减脂目标、目标体重与日期',
    ProfileSection.preferences => '饮食方式、过敏与禁忌',
    ProfileSection.risk => '更新后立即应用安全限制',
  };
}
