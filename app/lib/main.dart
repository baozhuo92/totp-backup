import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'services/lock_service.dart';
import 'ui/pages/account_list_page.dart';
import 'ui/pages/lock_page.dart';
import 'ui/pages/setup_page.dart';

void main() {
  runApp(const TotpApp());
}

/// 全局 SnackBar 脚手架 key：供后台任务（如扫码页 pop 后的加密入库、
/// 同步完成）在任意页面弹出提示。
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 应用根组件：装配 zolysoft 主题（明暗跟随系统）
class TotpApp extends StatelessWidget {
  const TotpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOTP 备份',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const RootGate(),
    );
  }
}

/// 启动路由门卫：
/// 未配置 → 设置页；已配置未解锁 → 锁页；已解锁 → 账户列表。
/// 注意：设置页/锁页完成动作后自行 pushReplacement 到账户列表，
/// 本组件只在冷启动时判定一次（LockService 为进程内单例状态）。
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _loading = true;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final configured = await LockService.instance.isConfigured();
    if (mounted) {
      setState(() {
        _configured = configured;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // 加载中状态（首次判断配置，通常很快）
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_configured) return const SetupPage();
    if (!LockService.instance.isUnlocked) return const LockPage();
    return const AccountListPage();
  }
}
