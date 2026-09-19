import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local/account_repository.dart';
import '../../data/models/totp_account.dart';
import '../../services/account_cache.dart';
import '../../services/lock_service.dart';
import '../../services/sync_service.dart';
import '../../services/totp_exchange_service.dart';

/// 导入/导出页（剪贴板 otpauth 文本方案，零文件权限依赖）。
///
/// - 导出：全部账户 → otpauth URI 文本 → 复制到剪贴板
/// - 导入：粘贴文本 → 解析预览 → 确认后逐条入库（同 issuer+account 已存在则跳过）
///   导入成功的账户自动入同步队列上传服务端
class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  final _importController = TextEditingController();
  List<TOTPAccount> _parsed = const [];
  bool _importing = false;

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  /// 复制导出文本到剪贴板
  Future<void> _export() async {
    // 仅导出已解密的账户（未解密条目无明文 secret，无法导出）
    final all = AccountCache.instance.accounts;
    final accounts =
        all.where((a) => a.hasSecret).map((a) => a.toAccount()).toList();
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(all.isEmpty ? '暂无账户可导出' : '账户仍在解密中，请稍候再导出')));
      return;
    }
    final text = TotpExchangeService.exportToText(accounts);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已复制 ${accounts.length} 个账户的 otpauth 文本')));
  }

  /// 解析输入文本（实时预览识别数量）
  void _parseInput() {
    setState(() {
      _parsed = TotpExchangeService.parseImportText(_importController.text);
    });
  }

  /// 执行导入：跳过已存在（issuer+account 相同），新账户入库并入队同步。
  /// 导入前弹确认：导入的账户会以导入文件为准上传覆盖服务端同名账户，
  /// 避免旧备份回退线上数据（防误覆盖）。
  Future<void> _import() async {
    if (_parsed.isEmpty) return;
    final pwd = LockService.instance.masterPassword;
    if (pwd == null) return;
    // 确认提示：导入账户会同步上传并覆盖服务端同名账户
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: Text('将导入 ${_parsed.length} 个账户。\n'
            '导入的账户会以导入文件为准上传到服务端，'
            '并覆盖服务端上的同名账户（防止旧备份回退线上数据）。\n'
            '确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _importing = true);
    try {
      final existingKeys = AccountCache.instance.accounts
          .map((a) => _dupKey(a.issuer, a.account))
          .toSet();
      var added = 0;
      for (final account in _parsed) {
        if (existingKeys.contains(_dupKey(account.issuer, account.account))) {
          continue; // 已存在，跳过
        }
        await AccountRepository().insert(account, pwd);
        await SyncService.instance.enqueueAddOrUpdate(account);
        added++;
        existingKeys.add(_dupKey(account.issuer, account.account));
      }
      await AccountCache.instance.reload();
      SyncService.instance.flush();
      if (!mounted) return;
      final skipped = _parsed.length - added;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('导入完成：新增 $added 个，跳过 $skipped 个（已存在）')));
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 去重键（issuer + account，忽略大小写）
  String _dupKey(String issuer, String account) =>
      '${issuer.toLowerCase()}|${account.toLowerCase()}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入 / 导出')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- 导出区 ----
              Text('导出', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '将所有账户导出为 otpauth:// 文本并复制到剪贴板。'
                '文本含明文密钥，请注意传输渠道安全（如加密聊天）。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.copy_all),
                label: const Text('复制导出文本'),
              ),
              const SizedBox(height: 24),

              // ---- 导入区 ----
              Text('导入', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '粘贴 otpauth:// 文本（每行一个，可从其他验证器导出）。'
                '已存在的账户（同名服务+账号）将自动跳过。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _importController,
                maxLines: 6,
                onChanged: (_) => _parseInput(),
                decoration: const InputDecoration(
                  hintText: '粘贴 otpauth://totp/... 文本',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _parsed.isEmpty
                    ? '未识别到有效账户'
                    : '识别到 ${_parsed.length} 个有效账户',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _parsed.isEmpty
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    (_parsed.isEmpty || _importing) ? null : _import,
                icon: const Icon(Icons.download),
                label: _importing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('导入 ${_parsed.length} 个账户'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
