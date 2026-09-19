import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/account_cache.dart';
import 'countdown_ring.dart';

/// 账户卡片：issuer + account（左），动态码（等宽大字）+ 倒计时圆环（右）。
/// 点击复制验证码；长按弹出操作菜单（编辑/删除，由父级回调决定）。
///
/// [code]/[remainingSeconds] 传 null 表示该账户 secret 尚未解密（后台解密中），
/// 动态码位置显示占位星号、不显示倒计时，避免解密完成前界面空白。
/// [syncStatus] 非空时在 issuer 行尾显示同步状态小图标：
/// 待同步（云上传·警示色）/ 已备份（云对勾·品牌色）。
class AccountCard extends StatelessWidget {
  final CachedAccount account;

  /// 当前时间步验证码（由列表页每秒计算传入）；null = 解密中占位
  final String? code;

  /// 当前时间步剩余秒数；null = 解密中占位
  final int? remainingSeconds;

  /// 同步状态（null = 从未同步，不显示图标）
  final AccountSyncStatus? syncStatus;

  /// 点击卡片（复制验证码）
  final VoidCallback? onTap;

  /// 长按卡片（弹出操作菜单）
  final VoidCallback? onLongPress;

  const AccountCard({
    super.key,
    required this.account,
    required this.code,
    required this.remainingSeconds,
    this.syncStatus,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decrypting = code == null;
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.issuer.isEmpty ? '未命名服务' : account.issuer,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 每账户同步状态小图标（待同步/已备份）
                        if (syncStatus != null) ...[
                          const SizedBox(width: 6),
                          _SyncStatusIcon(status: syncStatus!),
                        ],
                      ],
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
              // 等宽字体保证验证码数字对齐；解密中显示固定宽占位星号
              Text(
                decrypting ? '••••••' : code!,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: decrypting
                      ? theme.colorScheme.outline.withValues(alpha: 0.6)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              // 解密中不渲染倒计时圆环（避免误导）
              if (!decrypting)
                CountdownRing(
                  remainingSeconds: remainingSeconds ?? account.period,
                  period: account.period,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 同步状态小图标：待同步（上传箭头·警示色）/ 已备份（对勾·品牌色）
class _SyncStatusIcon extends StatelessWidget {
  final AccountSyncStatus status;
  const _SyncStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case AccountSyncStatus.pending:
        return Tooltip(
          message: '待同步（备份未成功上传，将自动重试）',
          child: const Icon(
            Icons.cloud_upload_outlined,
            size: 15,
            color: Colors.orange,
          ),
        );
      case AccountSyncStatus.backedUp:
        return Tooltip(
          message: '已备份到服务端',
          child: const Icon(
            Icons.cloud_done_outlined,
            size: 15,
            color: AppTheme.brand,
          ),
        );
    }
  }
}
