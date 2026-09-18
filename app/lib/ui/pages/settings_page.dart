import 'package:flutter/material.dart';

import '../../data/local/settings_repository.dart';

/// 设置页：编辑服务端地址与 API Key（secure storage）。
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
    if (!mounted) return;
    setState(() {
      _serverController.text = url ?? '';
      _apiKeyController.text = key ?? '';
      _loading = false;
    });
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
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
