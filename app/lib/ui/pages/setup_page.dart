import 'package:flutter/material.dart';

import '../../data/local/settings_repository.dart';
import '../../services/lock_service.dart';
import 'account_list_page.dart';

/// 首次引导/设置页（zolysoft UI 规范：表单标签 + 必填星号 + 错误红字）。
/// 配置服务端地址、API Key 与主口令；主口令用于端到端加密与换机恢复。
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _biometricSupported = false;
  bool _enableBiometric = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _apiKeyController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 检测设备生物识别能力（决定是否显示指纹开关）
  Future<void> _checkBiometric() async {
    final supported = await LockService.instance.isBiometricAvailable();
    if (mounted) {
      setState(() => _biometricSupported = supported);
    }
  }

  /// 保存配置：secure storage 存服务端地址/API Key，设置主口令（可启用指纹）
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SettingsRepository.instance.saveServerConfig(
        serverUrl: _serverController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      );
      await LockService.instance.setupMasterPassword(
        _passwordController.text,
        enableBiometric: _enableBiometric && _biometricSupported,
      );
      if (!mounted) return;
      // 保存成功进入账户列表（替换当前页，防止返回设置页）
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AccountListPage()),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('首次设置')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('配置备份服务', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '填写自建服务端信息并设置主口令。'
                  '主口令用于加密备份数据，换机恢复时需输入相同口令。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _serverController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务端地址 *',
                    hintText: 'https://totp.example.com',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return '请输入服务端地址';
                    final uri = Uri.tryParse(s);
                    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
                      return '地址须为 http(s):// 开头';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key *',
                    hintText: '服务端 .env 中配置的密钥',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '主口令 *',
                    hintText: '至少 8 位，请务必牢记',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '请输入主口令';
                    if (v.length < 8) return '主口令至少 8 位';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认主口令 *',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) {
                    if (v != _passwordController.text) return '两次输入不一致';
                    return null;
                  },
                ),
                if (_biometricSupported) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用指纹解锁'),
                    subtitle: const Text('解锁时通过指纹获取主口令（Android Keystore 保护）'),
                    value: _enableBiometric,
                    onChanged: (v) => setState(() => _enableBiometric = v),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存并进入'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
