import 'package:flutter/material.dart';

import '../../data/models/totp_account.dart';
import 'countdown_ring.dart';

/// 账户卡片：issuer + account（左），动态码（等宽大字）+ 倒计时圆环（右）。
/// 点击复制验证码；长按弹出操作菜单（编辑/删除，由父级回调决定）。
class AccountCard extends StatelessWidget {
  final TOTPAccount account;

  /// 当前时间步验证码（由列表页每秒计算传入）
  final String code;

  /// 当前时间步剩余秒数
  final int remainingSeconds;

  /// 点击卡片（复制验证码）
  final VoidCallback? onTap;

  /// 长按卡片（弹出操作菜单）
  final VoidCallback? onLongPress;

  const AccountCard({
    super.key,
    required this.account,
    required this.code,
    required this.remainingSeconds,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.issuer.isEmpty ? '未命名服务' : account.issuer,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.account,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 等宽字体保证验证码数字对齐
              Text(
                code,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 12),
              CountdownRing(
                remainingSeconds: remainingSeconds,
                period: account.period,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
