import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';

class DeletionPendingPage extends StatefulWidget {
  const DeletionPendingPage({required this.session, super.key});
  final SessionController session;

  @override
  State<DeletionPendingPage> createState() => _DeletionPendingPageState();
}

class _DeletionPendingPageState extends State<DeletionPendingPage> {
  Map<String, dynamic>? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.session.api.getAccountDeletion();
      if (mounted) setState(() => _status = value);
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    }
  }

  Future<void> _recover() async {
    final phone = widget.session.phone;
    if (phone == null) {
      setState(() => _error = '请退出后使用绑定手机号重新登录');
      return;
    }
    setState(() => _busy = true);
    try {
      final debugCode = await widget.session.api.sendPurposeCode(
        phone,
        'ACCOUNT_RECOVER',
      );
      if (!mounted) return;
      final code = await _codeDialog(debugCode);
      if (code == null) return;
      await widget.session.api.recoverAccount(code);
      await widget.session.accountRecovered();
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _codeDialog(String? debugCode) {
    final controller = TextEditingController(text: debugCode);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('验证绑定手机号'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '验证码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('恢复账户'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_status?['remainingSeconds'] as num?)?.toInt();
    final days = seconds == null ? null : (seconds / 86400).ceil();
    return Scaffold(
      appBar: AppBar(title: const Text('注销处理中')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.schedule_outlined, size: 52),
            const SizedBox(height: 18),
            Text(
              '账户正在 7 天冷静期内',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(days == null ? '正在读取剩余时间…' : '距离永久注销约剩 $days 天。恢复前不能使用健康功能。'),
            if (_status?['requestedAt'] != null) ...[
              const SizedBox(height: 18),
              Text('申请时间：${_status!['requestedAt']}'),
              Text('永久注销时间：${_status!['scheduledFor']}'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _recover,
              child: Text(_busy ? '处理中…' : '恢复账户'),
            ),
            TextButton(
              onPressed: _busy ? null : widget.session.logout,
              child: const Text('退出登录'),
            ),
          ],
        ),
      ),
    );
  }
}
