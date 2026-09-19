import 'package:flutter/material.dart';

import '../../data/local/settings_repository.dart';
import '../../services/lock_service.dart';
import '../../services/sync_service.dart';

/// 设置页：编辑服务端地址与 API Key（t_settings），指纹解锁开关，立即手动同步。
///
/// 说明：主口令不支持在此修改——端到端加密下换口令需全量重加密，
/// 属数据迁移类操作，不在当前版本范围（如需要可后续单独增加）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverController;
  late final TextEditingController _apiKeyController;
  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController();
    _apiKeyController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 预填现有配置
  Future<void> _load() async {
    final url = await SettingsRepository.instance.getServerUrl();
    final key = await SettingsRepository.instance.getApiKey();
    final supported = await LockService.instance.isBiometricAvailable();
    final enabled = await LockService.instance.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _serverController.text = url ?? '';
      _apiKeyController.text = key ?? '';
      _biometricSupported = supported;
      _biometricEnabled = enabled;
      _loading = false;
    });
  }

  /// 指纹解锁开关：开启需写入 biometric 主口令（弹系统指纹授权）
  Future<void> _toggleBiometric(bool value) async {
    setState(() => _biometricEnabled = value); // 乐观更新
    final bool ok;
    if (value) {
      ok = await LockService.instance.enableBiometric();
    } else {
      await LockService.instance.disableBiometric();
      ok = true;
    }
    if (!mounted) return;
    if (value && !ok) {
      // 用户取消指纹授权或写入失败：回滚开关状态
      setState(() => _biometricEnabled = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('指纹授权未完成，未启用指纹解锁')));
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(value ? '已启用指纹解锁' : '已关闭指纹解锁')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SettingsRepository.instance.saveServerConfig(
        serverUrl: _serverController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('设置已保存')));
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 立即手动同步（不依赖表单有效性，队列为空时提示）
  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final ok = await SyncService.instance.flush();
    if (!mounted) return;
    setState(() => _syncing = false);
    final sync = SyncService.instance;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? '同步完成，全部已备份到服务端'
            : '同步失败：${sync.lastError ?? '网络异常'}，已加入重试队列'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _serverController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '服务端地址',
                          hintText: 'https://totp.example.com',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return '请输入服务端地址';
                          final uri = Uri.tryParse(s);
                          if (uri == null ||
                              !(uri.isScheme('http') || uri.isScheme('https'))) {
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
                          labelText: 'API Key',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '请输入 API Key'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      // 指纹解锁开关（设备支持且已设置主口令时可用）
                      if (_biometricSupported) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('指纹解锁'),
                          subtitle: const Text('用指纹代替主口令解锁 App'),
                          value: _biometricEnabled,
                          onChanged: _toggleBiometric,
                        ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('保存'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _syncing ? null : _syncNow,
                        icon: _syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: const Text('立即同步'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
