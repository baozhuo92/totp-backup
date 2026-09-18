import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/local/account_repository.dart';
import '../../data/models/totp_account.dart';
import '../../services/account_cache.dart';
import '../../services/lock_service.dart';

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

  /// 入库并刷新缓存（同步由任务 9 的 SyncService 统一处理）
  Future<void> _save(TOTPAccount account) async {
    final pwd = LockService.instance.masterPassword;
    if (pwd == null) return;
    await AccountRepository().insert(account, pwd);
    await AccountCache.instance.reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已添加 ${account.issuer}')));
    Navigator.pop(context);
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
