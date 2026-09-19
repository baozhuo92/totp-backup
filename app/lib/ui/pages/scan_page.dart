import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/local/account_repository.dart';
import '../../data/models/totp_account.dart';
import '../../main.dart' show appMessengerKey;
import '../../services/account_cache.dart';
import '../../services/lock_service.dart';
import '../../services/sync_service.dart';

/// 扫码添加页：识别 otpauth:// URI，确认后入库并刷新缓存。
/// 无效二维码提示后继续扫描；相机权限拒绝由 MobileScanner 内部错误状态处理。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// 防止同一帧重复处理
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 扫码回调：解析 URI → 确认弹窗 → 入库
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _processing = true);
    try {
      final account = TOTPAccount.fromOtpauthUri(raw);
      final confirmed = await _confirmAdd(account);
      if (!mounted) return;
      if (confirmed) {
        await _save(account);
      } else {
        // 用户取消：恢复扫描
        setState(() => _processing = false);
      }
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _processing = false);
    }
  }

  /// 添加确认弹窗（预览解析结果）
  Future<bool> _confirmAdd(TOTPAccount account) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加账户'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('服务：${account.issuer.isEmpty ? '未命名' : account.issuer}',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('账号：${account.account}'),
            const SizedBox(height: 4),
            Text('配置：${account.algorithm} · ${account.digits} 位 · '
                '${account.period} 秒'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 确认添加：立即返回列表（秒级反馈），加密入库/同步后台执行
  Future<void> _save(TOTPAccount account) async {
    final pwd = LockService.instance.masterPassword;
    if (pwd == null) return;
    if (!mounted) return;
    Navigator.pop(context); // 先关扫码页，避免等待加密耗时
    unawaited(_persist(account, pwd));
  }

  /// 后台持久化：加密入库 → 缓存元数据秒出 → 入队同步并尝试 → 全量两阶段重载
  Future<void> _persist(TOTPAccount account, String pwd) async {
    try {
      await AccountRepository().insert(account, pwd);
      // 立即把新账户元数据插入缓存（列表先显示信息，动态码后台解密）
      AccountCache.instance.insertMeta(account);
      await SyncService.instance.enqueueAddOrUpdate(account);
      final ok = await SyncService.instance.flush();
      await AccountCache.instance.reload();
      appMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(ok
              ? '已添加 ${account.issuer} 并备份到服务端'
              : '已添加 ${account.issuer}，备份失败已入重试队列'),
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
      appBar: AppBar(title: const Text('扫码添加')),
      body: Stack(
        children: [
          // 全屏扫码（相机权限由 mobile_scanner 插件处理）
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // 底部扫描引导文案
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(12),
              child: const Text(
                '对准 otpauth:// 二维码进行扫描',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
