import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

void main() {
  runApp(const TotpApp());
}

/// 应用根组件：装配 zolysoft 主题（明暗跟随系统）
class TotpApp extends StatelessWidget {
  const TotpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOTP 备份',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      // 任务 6 接入启动路由：无配置→设置页，有配置未解锁→锁页，已解锁→账户列表
      home: const Scaffold(
        body: Center(child: Text('TOTP 备份')),
      ),
    );
  }
}
