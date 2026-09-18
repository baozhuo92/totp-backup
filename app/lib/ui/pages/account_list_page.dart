import 'package:flutter/material.dart';

/// 账户列表页（主界面）。
/// 任务 6 阶段为占位实现，任务 7 完整实现（动态码/倒计时/搜索等）。
class AccountListPage extends StatelessWidget {
  const AccountListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账户')),
      body: const Center(child: Text('账户列表（任务 7 实现）')),
    );
  }
}
