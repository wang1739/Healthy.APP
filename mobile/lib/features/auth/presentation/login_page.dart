import 'package:flutter/material.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/core/theme/app_colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({required this.api, required this.onLoggedIn, super.key});

  final ApiClient api;
  final ValueChanged<LoginResult> onLoggedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _passwordMode = false;
  bool _accepted = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text)) {
      setState(() => _message = '请输入正确的手机号');
      return;
    }
    await _run(() async {
      final debugCode = await widget.api.sendCode(_phone.text);
      if (debugCode != null) _code.text = debugCode;
      setState(() => _message = debugCode == null ? '验证码已发送' : '开发验证码已自动填入');
    });
  }

  Future<void> _login() async {
    if (!_accepted) {
      setState(() => _message = '请先同意用户协议与隐私政策');
      return;
    }
    await _run(() async {
      final deviceName = Theme.of(context).platform == TargetPlatform.android
          ? 'Android 手机'
          : 'iPhone';
      final result = _passwordMode
          ? await widget.api.passwordLogin(
              phone: _phone.text,
              password: _password.text,
              deviceName: deviceName,
            )
          : await widget.api.smsLogin(
              phone: _phone.text,
              code: _code.text,
              password: _password.text,
              deviceName: deviceName,
            );
      widget.onLoggedIn(result);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Logo(),
                  const SizedBox(height: 34),
                  Text(
                    '欢迎来到轻食记',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('登录后建立健康档案，获得适合你的生活计划。'),
                  const SizedBox(height: 26),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('验证码登录')),
                      ButtonSegment(value: true, label: Text('密码登录')),
                    ],
                    selected: {_passwordMode},
                    onSelectionChanged: (value) =>
                        setState(() => _passwordMode = value.first),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_passwordMode) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: '验证码',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed: _busy ? null : _sendCode,
                            child: const Text('获取验证码'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: _passwordMode ? '密码' : '设置密码（可选，至少 8 位）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: _accepted,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setState(() => _accepted = value ?? false),
                    title: const Text('我已阅读并同意《用户协议》与《隐私政策》'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _message!,
                      style: const TextStyle(color: AppColors.green),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: Text(_busy ? '请稍候…' : '登录并继续'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '轻',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
