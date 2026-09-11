import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';

class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({
    required this.api,
    required this.phone,
    super.key,
  });
  final ApiClient api;
  final String phone;
  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.api.getDevices();
      if (mounted) setState(() => _items = value);
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<void> _remove(String id) async {
    await widget.api.removeDevice(id);
    await _load();
  }

  Future<void> _logoutOthers() async {
    try {
      final debug = await widget.api.sendPurposeCode(
        widget.phone,
        'LOGOUT_OTHER_DEVICES',
      );
      if (!mounted) return;
      final code = await askCode(context, '退出其他所有设备', debug);
      if (code == null) return;
      await widget.api.logoutOtherDevices(code);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备管理')),
    body: _items == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Text(_error!),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ..._items!.map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(
                      item['currentDevice'] == true
                          ? Icons.phone_android
                          : Icons.devices_other,
                    ),
                    title: Text(item['name']?.toString() ?? '未知设备'),
                    subtitle: Text(
                      '${item['system'] ?? '系统未知'} · 最近活跃 ${item['lastSeenAt'] ?? '未知'}',
                    ),
                    trailing: item['currentDevice'] == true
                        ? const Text('当前设备')
                        : TextButton(
                            onPressed: () => _remove(item['id'].toString()),
                            child: const Text('移除'),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _logoutOthers,
                child: const Text('退出其他所有设备'),
              ),
            ],
          ),
  );
}

class SecurityEventsPage extends StatelessWidget {
  const SecurityEventsPage({required this.api, super.key});
  final ApiClient api;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('安全记录')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: api.getSecurityEvents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(ApiClient.errorMessage(snapshot.error!)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) return const Center(child: Text('暂无安全记录'));
        return ListView(
          children: snapshot.data!
              .map(
                (item) => ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(item['type']?.toString() ?? '安全操作'),
                  subtitle: Text(
                    '${item['deviceName'] ?? '设备未知'} · ${item['createdAt'] ?? ''}',
                  ),
                  trailing: Text(item['result']?.toString() ?? ''),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class PrivacyCenterPage extends StatefulWidget {
  const PrivacyCenterPage({required this.api, super.key});
  final ApiClient api;
  @override
  State<PrivacyCenterPage> createState() => _PrivacyCenterPageState();
}

class _PrivacyCenterPageState extends State<PrivacyCenterPage> {
  Map<String, dynamic>? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.api.getPrivacy();
      if (mounted) {
        setState(() {
          _data = value;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  Future<void> _toggleHealth() async {
    final enabled = _data?['healthAuthorized'] == true;
    try {
      if (enabled) {
        final ok =
            await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('撤回健康数据授权？'),
                content: const Text('个性化计划、健康记录和报告将立即停用；现有数据暂时保留，重新同意后可恢复。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认撤回'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!ok) return;
        await widget.api.withdrawHealthAuthorization();
      } else {
        final docs = (_data?['latestDocuments'] as List? ?? []).cast<Map>();
        Map? doc;
        for (final item in docs) {
          if (item['type'] == 'HEALTH_DATA_AUTHORIZATION') doc = item;
        }
        if (doc == null) throw const FormatException('未找到健康数据授权文件');
        await widget.api.acceptConsent(
          'HEALTH_DATA_AUTHORIZATION',
          doc['version'].toString(),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('隐私中心')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!),
        ),
      );
    }
    final docs = (_data!['latestDocuments'] as List? ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(title: const Text('隐私中心')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('健康数据授权'),
            subtitle: Text(
              _data!['healthAuthorized'] == true ? '已授权，健康功能可用' : '已撤回，健康功能已停用',
            ),
            value: _data!['healthAuthorized'] == true,
            onChanged: (_) => _toggleHealth(),
          ),
          const Divider(),
          ...docs.map(
            (doc) => ListTile(
              title: Text(
                doc['type'] == 'PRIVACY_POLICY' ? '隐私政策' : '健康数据授权说明',
              ),
              subtitle: Text('版本 ${doc['version']} · ${doc['changeSummary']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _DocumentPage(document: doc)),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentPage extends StatelessWidget {
  const _DocumentPage({required this.document});
  final Map document;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(document['type'] == 'PRIVACY_POLICY' ? '隐私政策' : '健康数据授权说明'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '版本 ${document['version']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(document['changeSummary']?.toString() ?? ''),
        const Divider(height: 32),
        Text(
          document['content']?.toString() ??
              document['contentText']?.toString() ??
              '',
        ),
      ],
    ),
  );
}

class PhoneChangePage extends StatefulWidget {
  const PhoneChangePage({required this.api, required this.oldPhone, super.key});
  final ApiClient api;
  final String oldPhone;
  @override
  State<PhoneChangePage> createState() => _PhoneChangePageState();
}

class _PhoneChangePageState extends State<PhoneChangePage> {
  final newPhone = TextEditingController();
  final oldCode = TextEditingController();
  final newCode = TextEditingController();
  String? message;
  bool busy = false;
  @override
  void dispose() {
    newPhone.dispose();
    oldCode.dispose();
    newCode.dispose();
    super.dispose();
  }

  Future<void> _send(
    String phone,
    TextEditingController target,
    String purpose,
  ) async {
    try {
      final debug = await widget.api.sendPurposeCode(phone, purpose);
      if (debug != null) target.text = debug;
      setState(() => message = '验证码已发送');
    } catch (e) {
      setState(() => message = ApiClient.errorMessage(e));
    }
  }

  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      await widget.api.changePhone(
        oldCode: oldCode.text,
        newPhone: newPhone.text,
        newCode: newCode.text,
      );
      if (mounted) setState(() => message = '手机号已更换，其他设备已退出');
    } catch (e) {
      if (mounted) setState(() => message = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _appeal() async {
    final material = await askText(context, '人工申诉', '说明旧手机号无法使用的情况');
    if (material == null) return;
    try {
      await widget.api.submitPhoneAppeal(
        newPhone: newPhone.text,
        materialReference: material,
      );
      if (mounted) setState(() => message = '申诉已提交，请等待人工处理');
    } catch (e) {
      if (mounted) setState(() => message = ApiClient.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('更换手机号')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '当前手机号：${widget.oldPhone.substring(0, 3)}****${widget.oldPhone.substring(7)}',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: oldCode,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '旧手机号验证码',
            suffixIcon: TextButton(
              onPressed: () => _send(widget.oldPhone, oldCode, 'PHONE_OLD'),
              child: const Text('获取'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: newPhone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: '新手机号'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: newCode,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '新手机号验证码',
            suffixIcon: TextButton(
              onPressed: () => _send(newPhone.text, newCode, 'PHONE_NEW'),
              child: const Text('获取'),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(busy ? '处理中…' : '确认更换'),
        ),
        TextButton(onPressed: _appeal, child: const Text('旧手机号无法使用，进入人工申诉')),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message!),
          ),
      ],
    ),
  );
}

class DataRightsPage extends StatefulWidget {
  const DataRightsPage({required this.api, required this.phone, super.key});
  final ApiClient api;
  final String phone;
  @override
  State<DataRightsPage> createState() => _DataRightsPageState();
}

class _DataRightsPageState extends State<DataRightsPage> {
  final password = TextEditingController();
  String? message;
  bool busy = false;
  @override
  void dispose() {
    password.clear();
    password.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => busy = true);
    try {
      final debug = await widget.api.sendPurposeCode(
        widget.phone,
        'DATA_EXPORT',
      );
      if (!mounted) return;
      final code = await askCode(context, '申请数据导出', debug);
      if (code == null) return;
      await widget.api.createDataExport(code: code, password: password.text);
      if (mounted) setState(() => message = '中文加密 PDF 已生成，可在导出记录中下载');
    } catch (e) {
      if (mounted) setState(() => message = ApiClient.errorMessage(e));
    } finally {
      password.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => busy = true);
    try {
      final impact = await widget.api.previewHealthDataDeletion(['ALL']);
      if (!mounted) return;
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('永久删除全部健康数据？'),
              content: Text(
                '${impact['warning']}\n受影响报告：${impact['affectedReports']} 份。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('继续验证'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
      final debug = await widget.api.sendPurposeCode(
        widget.phone,
        'HEALTH_DATA_DELETE',
      );
      if (!mounted) return;
      final code = await askCode(context, '确认永久删除', debug);
      if (code == null) return;
      await widget.api.deleteHealthData(['ALL'], code);
      if (mounted) setState(() => message = '健康数据已永久删除');
    } catch (e) {
      if (mounted) setState(() => message = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('数据权利')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('导出个人数据', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('导出为中文 PDF，包含账户、健康档案、计划和健康记录，手机号会脱敏。'),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: '设置 PDF 密码（8—32 位）'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : _export,
          child: const Text('申请数据导出'),
        ),
        const Divider(height: 40),
        Text('删除健康数据', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('删除无法恢复；包含源数据的报告版本会同步删除，无关时间段报告保留。'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : _delete,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('永久删除全部健康数据'),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(message!),
          ),
      ],
    ),
  );
}

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({
    required this.session,
    required this.phone,
    super.key,
  });
  final SessionController session;
  final String phone;
  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  bool busy = false;
  String? error;
  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      final debug = await widget.session.api.sendPurposeCode(
        widget.phone,
        'ACCOUNT_DELETE',
      );
      if (!mounted) return;
      final code = await askCode(context, '申请注销账户', debug);
      if (code == null) return;
      await widget.session.api.requestAccountDeletion(code);
      await widget.session.accountDeletionRequested();
    } catch (e) {
      if (mounted) setState(() => error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('注销账户')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('注销账户前请确认', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        const Text(
          '• 申请后全部设备立即退出\n• 7 天冷静期内登录只能恢复账户\n• 冷静期结束后账户与业务数据永久清理\n• 未完成的数据导出会被取消',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(busy ? '处理中…' : '申请注销账户'),
        ),
      ],
    ),
  );
}

Future<String?> askCode(
  BuildContext context,
  String title,
  String? debugCode,
) async {
  final controller = TextEditingController(text: debugCode);
  final value = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(labelText: '短信验证码'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

Future<String?> askText(
  BuildContext context,
  String title,
  String label,
) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLength: 500,
        maxLines: 4,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('提交'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}
