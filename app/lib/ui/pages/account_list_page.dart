import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/local/account_repository.dart';
import '../../data/models/totp_account.dart';
import '../../services/account_cache.dart';
import '../../services/sync_service.dart';
import '../../services/totp_service.dart';
import '../widgets/account_card.dart';
import 'import_export_page.dart';
import 'manual_add_page.dart';
import 'restore_page.dart';
import 'scan_page.dart';
import 'settings_page.dart';

/// 账户列表主界面：动态码卡片 + 倒计时圆环 + 搜索 + 空状态。
/// 数据源为 AccountCache（内存明文缓存，解锁后加载），每秒重绘一次刷新验证码。
class AccountListPage extends StatefulWidget {
  const AccountListPage({super.key});

  @override
  State<AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends State<AccountListPage> {
  Timer? _ticker;
  Timer? _syncTicker;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // 首次进入加载缓存（解锁后主口令已在内存）
    if (!AccountCache.instance.loaded) {
      AccountCache.instance.reload();
    }
    // 每秒重绘：动态码与倒计时圆环随秒刷新
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // 每 60 秒尝试清空同步队列（自动重试失败的备份）
    _syncTicker = Timer.periodic(const Duration(seconds: 60), (_) {
      SyncService.instance.flush();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _syncTicker?.cancel();
    super.dispose();
  }

  /// 点击卡片复制验证码
  Future<void> _copyCode(TOTPAccount account) async {
    final code = TotpService.currentCode(account);
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('验证码 $code 已复制')));
  }

  /// AppBar 更多菜单（恢复/导入导出/设置入口，对应任务 10/11/12 接入）
  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('从服务端恢复'),
              onTap: () {
                Navigator.pop(ctx);
                _openRestorePage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('导入/导出备份文件'),
              onTap: () {
                Navigator.pop(ctx);
                _openImportExportPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.pop(ctx);
                _openSettingsPage();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 添加菜单（扫码/手动添加）
  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('扫码添加'),
              onTap: () {
                Navigator.pop(ctx);
                _openScanPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('手动添加'),
              onTap: () {
                Navigator.pop(ctx);
                _openManualAddPage();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openScanPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
  }

  Future<void> _openManualAddPage({TOTPAccount? existing}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ManualAddPage(existing: existing)),
    );
  }

  Future<void> _openRestorePage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RestorePage()),
    );
  }

  Future<void> _openImportExportPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ImportExportPage()),
    );
  }

  Future<void> _openSettingsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onPressed: _showMoreMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框（按 issuer/account 过滤）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索服务或账号',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: AccountCache.instance,
              builder: (context, _) {
                final accounts = AccountCache.instance.search(_query);
                if (accounts.isEmpty) {
                  return _EmptyState(
                    hasAny: AccountCache.instance.accounts.isNotEmpty,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 88),
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final a = accounts[index];
                    return AccountCard(
                      account: a,
                      code: TotpService.currentCode(a),
                      remainingSeconds: TotpService.remainingSeconds(a.period),
                      onTap: () => _copyCode(a),
                      onLongPress: () => _showAccountMenu(a),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加账户',
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 删除账户：确认后本地删除 + 入队 DELETE 并尝试同步
  Future<void> _deleteAccount(TOTPAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除 ${account.issuer}（${account.account}）？\n'
            '删除后将同步到服务端备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AccountRepository().delete(account.clientId);
    await AccountCache.instance.reload();
    await SyncService.instance.enqueueDelete(account.clientId);
    SyncService.instance.flush();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已删除 ${account.issuer}')));
  }

  /// 长按账户操作菜单（编辑/删除）
  void _showAccountMenu(TOTPAccount account) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制验证码'),
              onTap: () {
                Navigator.pop(ctx);
                _copyCode(account);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _openManualAddPage(existing: account);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('删除', style: TextStyle(color: AppTheme.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteAccount(account);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 空状态：无任何账户时显示引导；有账户但搜索无结果显示无匹配
class _EmptyState extends StatelessWidget {
  final bool hasAny;
  const _EmptyState({required this.hasAny});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasAny ? Icons.search_off : Icons.shield_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            hasAny ? '未找到匹配的账户' : '暂无账户',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!hasAny) ...[
            const SizedBox(height: 8),
            Text(
              '扫码或手动添加你的第一个 TOTP 账户',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
