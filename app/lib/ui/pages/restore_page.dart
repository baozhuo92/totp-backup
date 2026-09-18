import 'package:flutter/material.dart';

import '../../core/crypto/crypto_service.dart';
import '../../data/local/account_repository.dart';
import '../../data/local/settings_repository.dart';
import '../../data/models/totp_account.dart';
import '../../data/remote/api_client.dart';
import '../../services/account_cache.dart';
import '../../services/lock_service.dart';

/// 从服务端恢复页：拉取备份列表 → 确认 → 解密（当前主口令）→ 幂等入库 → 刷新缓存。
///
/// 安全设计：全部条目先用主口令成功解密，任一失败即整体中止（提示口令不匹配），
/// 避免"部分恢复 + 主口令错误"造成数据混乱。恢复时以服务端为准覆盖本地同名账户。
class RestorePage extends StatefulWidget {
  const RestorePage({super.key});

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  /// 页面四态：loading / error / empty / normal（zolysoft UI 规范）
  bool _loading = true;
  String? _error;
  List<RemoteAccount> _remote = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// 拉取服务端备份列表
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final serverUrl = await SettingsRepository.instance.getServerUrl();
      final apiKey = await SettingsRepository.instance.getApiKey();
      if (serverUrl == null || apiKey == null) {
        setState(() {
          _loading = false;
          _error = '未配置服务端，请先在设置中填写地址与 API Key';
        });
        return;
      }
      final client = ApiClient(baseUrl: serverUrl, apiKey: apiKey);
      final items = await client.fetchAll();
      if (!mounted) return;
      setState(() {
        _remote = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// 执行恢复：解密全部 → 幂等入库 → 刷新缓存
  Future<void> _restore() async {
    final pwd = LockService.instance.masterPassword;
    if (pwd == null) return;

    // 显示恢复进度对话框（PBKDF2 解密每条约 1 秒）
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在恢复备份…'),
          ],
        ),
      ),
    );

    try {
      // 阶段一：全部解密（任一失败 → 主口令不匹配，整体中止）
      final accounts = <TOTPAccount>[];
      for (final item in _remote) {
        final secret = await CryptoService.decrypt(
            item.secretCiphertext, pwd);
        accounts.add(TOTPAccount(
          clientId: item.clientId,
          issuer: item.issuer,
          account: item.account,
          secretBase32: secret,
          algorithm: item.algorithm,
          digits: item.digits,
          period: item.period,
        ));
      }

      // 阶段二：幂等入库（client_id 覆盖本地同名账户，服务端为准）
      for (final account in accounts) {
        await AccountRepository().insert(account, pwd);
      }
      await AccountCache.instance.reload();
      if (!mounted) return;
      Navigator.pop(context); // 关闭进度对话框
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已恢复 ${accounts.length} 个账户')));
      Navigator.pop(context); // 返回列表页
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭进度对话框
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复失败'),
          content: const Text('主口令与服务端备份不匹配，或备份数据已损坏。\n'
              '请确认使用加密备份时的同一主口令。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('从服务端恢复')),
      body: SafeArea(
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      // 错误态：文案 + 重试按钮
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _fetch, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_remote.isEmpty) {
      // 空态：服务端无备份
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('服务端暂无备份数据'),
          ],
        ),
      );
    }
    // 常态：备份预览 + 恢复按钮
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _remote.length,
            itemBuilder: (context, index) {
              final item = _remote[index];
              return ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(item.issuer),
                subtitle: Text(item.account),
                trailing: Text('${item.digits} 位'),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _restore,
            icon: const Icon(Icons.settings_backup_restore),
            label: Text('恢复 ${_remote.length} 个账户'),
          ),
        ),
      ],
    );
  }
}
