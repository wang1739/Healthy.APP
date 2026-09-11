import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';

class ProfileOverviewPage extends StatefulWidget {
  const ProfileOverviewPage({required this.session, super.key});
  final SessionController session;

  @override
  State<ProfileOverviewPage> createState() => _ProfileOverviewPageState();
}

class _ProfileOverviewPageState extends State<ProfileOverviewPage> {
  Map<String, dynamic>? state;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.session.api.profileCompleteness();
      if (mounted) setState(() => state = value);
    } catch (exception) {
      if (mounted) setState(() => error = ApiClient.errorMessage(exception));
    }
  }

  void _edit() {
    Navigator.of(context).pop();
    widget.session.openProfile();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('健康档案')),
    body: state == null
        ? Center(
            child: error == null
                ? const CircularProgressIndicator()
                : Text(error!),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state!['planNeedsRecalculation'] == true)
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('计划需要重新计算'),
                    subtitle: Text('旧计划和历史仍会保留，确认新计划后才会切换。'),
                  ),
                ),
              const SizedBox(height: 8),
              ...const [
                ('基本信息', '出生日期、性别、身高与代谢计算依据', Icons.badge_outlined),
                ('身体测量', '体重、腰围与体脂率', Icons.monitor_weight_outlined),
                ('生活方式', '活动水平、工作状态、睡眠与运动', Icons.directions_walk_outlined),
                ('健康目标', '主要目标、目标体重与目标日期', Icons.flag_outlined),
                ('饮食偏好', '饮食方式、过敏与禁忌', Icons.restaurant_menu_outlined),
                ('风险评估', '更新后立即应用安全限制', Icons.health_and_safety_outlined),
              ].map(
                (section) => Card(
                  child: ListTile(
                    leading: Icon(section.$3),
                    title: Text(section.$1),
                    subtitle: Text(section.$2),
                    trailing: const Text('编辑'),
                    onTap: _edit,
                  ),
                ),
              ),
            ],
          ),
  );
}
