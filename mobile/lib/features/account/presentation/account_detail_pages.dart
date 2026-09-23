import 'package:flutter/material.dart';
import 'package:healthy/app/session_controller.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/report/application/report_controller.dart';

const _healthDataTypeLabels = {
  'PROFILE': '健康档案',
  'MEASUREMENTS': '身体测量与关联计划',
  'NUTRITION': '饮食记录',
  'HYDRATION': '饮水记录',
  'ACTIVITY': '运动记录',
  'SLEEP': '睡眠记录',
  'TASKS': '任务记录',
  'PLANS': '计划版本',
  'REPORTS': '健康报告',
};

Map<String, Map<String, dynamic>> latestPrivacyDocuments(Iterable values) {
  final latest = <String, Map<String, dynamic>>{};
  for (final value in values) {
    final document = Map<String, dynamic>.from(value as Map);
    final type = document['type']?.toString() ?? '';
    final current = latest[type];
    final effectiveAt = DateTime.tryParse(
      document['effectiveAt']?.toString() ?? '',
    );
    final currentAt = DateTime.tryParse(
      current?['effectiveAt']?.toString() ?? '',
    );
    if (current == null ||
        (effectiveAt != null &&
            (currentAt == null || effectiveAt.isAfter(currentAt)))) {
      latest[type] = document;
    }
  }
  return latest;
}

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
  const PrivacyCenterPage({
    required this.api,
    required this.session,
    super.key,
  });
  final ApiClient api;
  final SessionController session;
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
        await widget.session.healthDataChanged(healthAuthorized: false);
      } else {
        final doc = latestPrivacyDocuments(
          _data?['latestDocuments'] as List? ?? const [],
        )['HEALTH_DATA_AUTHORIZATION'];
        if (doc == null) throw const FormatException('未找到健康数据授权文件');
        await widget.api.acceptConsent(
          'HEALTH_DATA_AUTHORIZATION',
          doc['version'].toString(),
        );
        await widget.session.healthDataChanged(healthAuthorized: true);
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
    final docs = latestPrivacyDocuments(
      _data!['latestDocuments'] as List? ?? const [],
    ).values.toList();
    final history = (_data!['history'] as List? ?? const []).cast<Map>();
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '隐私政策已同意版本：${_data!['acceptedPrivacyVersion'] ?? '暂无'}\n'
              '健康授权已同意版本：${_data!['acceptedHealthVersion'] ?? '暂无'}',
            ),
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
          if (history.isNotEmpty) ...[
            const Divider(height: 32),
            Text('同意与撤回历史', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...history.map(
              (event) => ListTile(
                dense: true,
                title: Text(
                  event['type'] == 'PRIVACY_POLICY' ? '隐私政策' : '健康数据授权',
                ),
                subtitle: Text(
                  '版本 ${event['version']} · ${event['createdAt'] ?? ''}',
                ),
                trailing: Text(event['action'] == 'ACCEPT' ? '已同意' : '已撤回'),
              ),
            ),
          ],
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
  const DataRightsPage({
    required this.api,
    required this.phone,
    required this.session,
    this.savePdf = saveReportPdfToTemporaryDirectory,
    super.key,
  });
  final ApiClient api;
  final String phone;
  final SessionController session;
  final SaveReportPdf savePdf;
  @override
  State<DataRightsPage> createState() => _DataRightsPageState();
}

class _DataRightsPageState extends State<DataRightsPage> {
  final password = TextEditingController();
  String? message;
  bool busy = false;
  bool loadingExports = true;
  List<Map<String, dynamic>> exports = const [];
  final selectedTypes = <String>{'ALL'};
  DateTime? fromDate;
  DateTime? toDate;

  static const deletionTypes = _healthDataTypeLabels;

  @override
  void initState() {
    super.initState();
    _loadExports();
  }

  @override
  void dispose() {
    password.clear();
    password.dispose();
    super.dispose();
  }

  Future<void> _loadExports() async {
    try {
      final value = await widget.api.getDataExports();
      if (mounted) {
        setState(() {
          exports = value;
          loadingExports = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = ApiClient.errorMessage(e);
          loadingExports = false;
        });
      }
    }
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
      await _loadExports();
      if (mounted) setState(() => message = '导出申请已提交，生成后可在下方下载');
    } catch (e) {
      if (mounted) setState(() => message = ApiClient.errorMessage(e));
    } finally {
      password.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _download(Map<String, dynamic> item) async {
    setState(() => busy = true);
    try {
      final pdf = await widget.api.downloadDataExportPdf(item['id'].toString());
      final path = await widget.savePdf(pdf.fileName, pdf.bytes);
      if (mounted) {
        final value = '加密 PDF 已保存至：$path';
        setState(() => message = value);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(value)));
      }
    } catch (e) {
      if (mounted) setState(() => message = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = (from ? fromDate : toDate) ?? DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: from ? '选择开始日期' : '选择结束日期',
    );
    if (value != null && mounted) {
      setState(() {
        if (from) {
          fromDate = value;
        } else {
          toDate = value;
        }
      });
    }
  }

  Future<void> _delete() async {
    setState(() => busy = true);
    try {
      final types = selectedTypes.toList(growable: false);
      if (types.isEmpty) throw const FormatException('请至少选择一种健康数据');
      if (fromDate != null && toDate != null && fromDate!.isAfter(toDate!)) {
        throw const FormatException('开始日期不能晚于结束日期');
      }
      final impact = await widget.api.previewHealthDataDeletion(
        types,
        fromDate: fromDate,
        toDate: toDate,
      );
      if (!mounted) return;
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('查看删除影响'),
              content: Text(
                '${impact['warning']}\n\n记录数量：${_impactCounts(impact['recordCounts'])}'
                '\n受影响报告：${impact['affectedReports'] ?? 0} 份'
                '\n受影响计划版本：${impact['affectedPlanVersions'] ?? 0} 个',
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
      if (!mounted) return;
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('最后确认永久删除'),
              content: const Text('此操作无法撤销。确认后，所选范围的数据及受影响报告会立即永久删除。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('返回检查'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认永久删除'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      await widget.api.deleteHealthData(
        types,
        code,
        fromDate: fromDate,
        toDate: toDate,
      );
      final deletesAll = types.contains('ALL');
      await widget.session.healthDataChanged(
        healthAuthorized: deletesAll ? false : null,
        profileDeleted: deletesAll || types.contains('PROFILE'),
      );
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
        const SizedBox(height: 6),
        const Text('导出文件使用你设置的密码加密，生成后 24 小时内可下载。'),
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
        const SizedBox(height: 16),
        Text('导出记录', style: Theme.of(context).textTheme.titleMedium),
        if (loadingExports)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (exports.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无导出记录'),
          )
        else
          ...exports.map(
            (item) => Card(
              child: ListTile(
                title: Text(_exportStatus(item)),
                subtitle: Text(
                  '申请时间：${item['createdAt'] ?? '未知'}\n'
                  '过期时间：${item['expiresAt'] ?? '生成完成后 24 小时'}',
                ),
                isThreeLine: true,
                trailing: _exportDownloadable(item)
                    ? TextButton(
                        onPressed: busy ? null : () => _download(item),
                        child: const Text('下载加密 PDF'),
                      )
                    : null,
              ),
            ),
          ),
        const Divider(height: 40),
        Text('删除健康数据', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('可按类型和时间范围删除；服务端会先计算影响。删除无法恢复，无关时间段报告保留。'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('全部健康数据'),
              selected: selectedTypes.contains('ALL'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              onSelected: busy
                  ? null
                  : (selected) => setState(() {
                      selectedTypes
                        ..clear()
                        ..addAll(selected ? const ['ALL'] : const []);
                    }),
            ),
            ...deletionTypes.entries.map(
              (entry) => FilterChip(
                label: Text(entry.value),
                selected: selectedTypes.contains(entry.key),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                onSelected: busy
                    ? null
                    : (selected) => setState(() {
                        selectedTypes.remove('ALL');
                        selected
                            ? selectedTypes.add(entry.key)
                            : selectedTypes.remove(entry.key);
                      }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: busy ? null : () => _pickDate(from: true),
              child: Text('开始：${_dateLabel(fromDate)}'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => _pickDate(from: false),
              child: Text('结束：${_dateLabel(toDate)}'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      fromDate = null;
                      toDate = null;
                    }),
              child: const Text('不限时间'),
            ),
          ],
        ),
        OutlinedButton(
          onPressed: busy ? null : _delete,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('预览影响并永久删除'),
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

String _dateLabel(DateTime? value) => value == null
    ? '不限'
    : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _exportStatus(Map<String, dynamic> item) => switch (item['status']) {
  'PENDING' || 'PROCESSING' => '生成中',
  'READY' when _exportExpired(item) => '已过期',
  'READY' => '可下载',
  'FAILED' => '生成失败',
  _ => '状态未知',
};

bool _exportDownloadable(Map<String, dynamic> item) =>
    item['status'] == 'READY' && !_exportExpired(item);

bool _exportExpired(Map<String, dynamic> item) {
  final expiresAt = DateTime.tryParse(item['expiresAt']?.toString() ?? '');
  return expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc());
}

String _impactCounts(Object? value) {
  if (value is! Map || value.isEmpty) return '0 条';
  return value.entries
      .map(
        (entry) =>
            '${_healthDataTypeLabels[entry.key.toString()] ?? '其他健康数据'} ${entry.value} 条',
      )
      .join('、');
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
