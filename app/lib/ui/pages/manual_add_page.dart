import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/account_repository.dart';
import '../../data/models/totp_account.dart';
import '../../main.dart' show appMessengerKey;
import '../../services/account_cache.dart';
import '../../services/lock_service.dart';
import '../../services/sync_service.dart';
import '../../services/totp_service.dart';

/// 手动添加/编辑账户页。
/// [existing] 为空 → 新增模式；非空 → 编辑模式（标题与保存路径不同）。
class ManualAddPage extends StatefulWidget {
  final TOTPAccount? existing;

  const ManualAddPage({super.key, this.existing});

  @override
  State<ManualAddPage> createState() => _ManualAddPageState();
}

class _ManualAddPageState extends State<ManualAddPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _issuerController;
  late final TextEditingController _accountController;
  late final TextEditingController _secretController;
  late final TextEditingController _verifyController;

  String _algorithm = 'SHA1';
  int _digits = 6;
  int _period = 30;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _issuerController = TextEditingController(text: e?.issuer ?? '');
    _accountController = TextEditingController(text: e?.account ?? '');
    _secretController = TextEditingController(text: e?.secretBase32 ?? '');
    _verifyController = TextEditingController();
    _algorithm = e?.algorithm ?? 'SHA1';
    _digits = e?.digits ?? 6;
    _period = e?.period ?? 30;
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _accountController.dispose();
    _secretController.dispose();
    _verifyController.dispose();
    super.dispose();
  }

  /// 保存：新增或编辑后入库并刷新缓存（同步由任务 9 统一处理）
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // 可选校验码：用待保存参数生成当前验证码对比，降低输错密钥风险
    final verifyInput = _verifyController.text.trim();
    if (verifyInput.isNotEmpty) {
      final probe = _isEdit
          ? TOTPAccount(
              clientId: widget.existing!.clientId,
              issuer: _issuerController.text.trim(),
              account: _accountController.text.trim(),
              secretBase32: _secretController.text.trim().toUpperCase(),
              algorithm: _algorithm,
              digits: _digits,
              period: _period,
            )
          : TOTPAccount.create(
              issuer: _issuerController.text.trim(),
              account: _accountController.text.trim(),
              secretBase32: _secretController.text.trim().toUpperCase(),
              algorithm: _algorithm,
              digits: _digits,
              period: _period,
            );
      final expected = TotpService.currentCode(probe);
      if (verifyInput != expected) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('校验码不正确，请检查密钥')));
        return;
      }
    }

    setState(() => _saving = true);
    final pwd = LockService.instance.masterPassword;
    if (pwd == null) {
      setState(() => _saving = false);
      return;
    }
    final secret = _secretController.text.trim().toUpperCase();
    final TOTPAccount account;
    if (_isEdit) {
      // 编辑模式：保留 clientId，走更新
      account = TOTPAccount(
        clientId: widget.existing!.clientId,
        issuer: _issuerController.text.trim(),
        account: _accountController.text.trim(),
        secretBase32: secret,
        algorithm: _algorithm,
        digits: _digits,
        period: _period,
      );
    } else {
      account = TOTPAccount.create(
        issuer: _issuerController.text.trim(),
        account: _accountController.text.trim(),
        secretBase32: secret,
        algorithm: _algorithm,
        digits: _digits,
        period: _period,
      );
    }
    // 立即返回列表（编辑/新增都秒级反馈），持久化与同步后台执行
    Navigator.pop(context, true);
    unawaited(_persist(account, pwd));
  }

  /// 后台持久化：加密入库/更新 → 缓存元数据秒出 → 入队同步并尝试 → 全量两阶段重载
  Future<void> _persist(TOTPAccount account, String pwd) async {
    try {
      if (_isEdit) {
        await AccountRepository().update(account, pwd);
      } else {
        await AccountRepository().insert(account, pwd);
        AccountCache.instance.insertMeta(account);
      }
      await SyncService.instance.enqueueAddOrUpdate(account);
      final ok = await SyncService.instance.flush();
      await AccountCache.instance.reload();
      appMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(ok
              ? '已保存并备份到服务端'
              : '已保存，备份失败已入重试队列'),
        ));
    } catch (_) {
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑账户' : '手动添加')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _issuerController,
                  decoration: const InputDecoration(
                    labelText: '服务名称 *',
                    hintText: '如 GitHub',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入服务名称' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _accountController,
                  decoration: const InputDecoration(
                    labelText: '账号 *',
                    hintText: '邮箱或用户名',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _secretController,
                  enabled: !_isEdit, // 编辑模式不允许改 secret（改密钥≈重建账户）
                  decoration: const InputDecoration(
                    labelText: '密钥（Base32）*',
                    hintText: '如 JBSWY3DPEHPK3PXP',
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return '请输入密钥';
                    // Base32 字符集校验（RFC 4648：A-Z 与 2-7）
                    final valid = RegExp(r'^[A-Za-z2-7]+=*$').hasMatch(s);
                    if (!valid) return '密钥须为 Base32 编码';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _verifyController,
                  decoration: const InputDecoration(
                    labelText: '校验码（可选）',
                    hintText: '填写当前 6 位验证码可校验密钥正确性',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _algorithm,
                  decoration: const InputDecoration(labelText: '算法'),
                  items: const [
                    DropdownMenuItem(value: 'SHA1', child: Text('SHA1')),
                    DropdownMenuItem(value: 'SHA256', child: Text('SHA256')),
                    DropdownMenuItem(value: 'SHA512', child: Text('SHA512')),
                  ],
                  onChanged: (v) => setState(() => _algorithm = v ?? 'SHA1'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _digits,
                        decoration: const InputDecoration(labelText: '位数'),
                        items: const [
                          DropdownMenuItem(value: 6, child: Text('6 位')),
                          DropdownMenuItem(value: 8, child: Text('8 位')),
                        ],
                        onChanged: (v) => setState(() => _digits = v ?? 6),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _period,
                        decoration: const InputDecoration(labelText: '周期'),
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 秒')),
                          DropdownMenuItem(value: 60, child: Text('60 秒')),
                        ],
                        onChanged: (v) => setState(() => _period = v ?? 30),
                      ),
                    ),
                  ],
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
                      : Text(_isEdit ? '保存修改' : '保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
