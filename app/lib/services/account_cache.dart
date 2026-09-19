import 'package:flutter/foundation.dart';

import '../core/crypto/crypto_service.dart';
import '../data/local/account_repository.dart';
import '../data/local/app_database.dart';
import '../data/models/totp_account.dart';
import 'lock_service.dart';

/// 账户同步状态（每账户轻量指示，卡片小图标）
enum AccountSyncStatus {
  /// 待同步：t_sync_queue 中仍有该账户未成功上传的变更（含失败重试中）
  pending,

  /// 已备份：最近一次同步成功（last_synced_time 非空）且当前不在队列
  backedUp,
}

/// 缓存中的账户条目：secret 可空（null 表示尚未解密）。
/// 列表页优先展示元数据（issuer/账号/参数），动态码区显示占位，
/// 后台解密完成后逐条填充，避免首页/添加后长时间空白。
class CachedAccount {
  final String clientId;
  final String issuer;
  final String account;
  final String algorithm;
  final int digits;
  final int period;

  /// 明文 Base32 密钥；null = 解密中，动态码显示占位星号
  final String? secretBase32;

  const CachedAccount({
    required this.clientId,
    required this.issuer,
    required this.account,
    required this.algorithm,
    required this.digits,
    required this.period,
    this.secretBase32,
  });

  /// 是否已解密（可计算动态码）
  bool get hasSecret => secretBase32 != null;

  /// 转完整 TOTPAccount（仅 secret 已解密时调用）
  TOTPAccount toAccount() => TOTPAccount(
        clientId: clientId,
        issuer: issuer,
        account: account,
        secretBase32: secretBase32 ?? '',
        algorithm: algorithm,
        digits: digits,
        period: period,
      );
}

/// 会话账户缓存（ChangeNotifier 单例）。
///
/// 两阶段加载（解决 PBKDF2 解密耗时导致的首页空白）：
/// - 阶段一：从本地库读取全部行，立即以元数据填充（不解密）并通知
/// - 阶段二：后台逐条解密，每完成一条通知一次（列表逐条出现动态码）
class AccountCache extends ChangeNotifier {
  AccountCache._();

  /// 单例
  static final AccountCache instance = AccountCache._();

  List<CachedAccount> _accounts = const [];
  bool _loaded = false;
  bool _decrypting = false;

  /// 每账户同步状态（clientId → 状态；无记录表示从未同步过）
  Map<String, AccountSyncStatus> _syncStates = const {};

  /// 账户列表（不可变视图）
  List<CachedAccount> get accounts => List.unmodifiable(_accounts);

  /// 是否已从本地库加载过元数据
  bool get loaded => _loaded;

  /// 是否正在后台解密（用于 UI 可选提示）
  bool get decrypting => _decrypting;

  /// 查询账户同步状态（无记录返回 null = 从未同步）
  AccountSyncStatus? syncStateOf(String clientId) => _syncStates[clientId];

  /// 按搜索词过滤（issuer/account 包含匹配，忽略大小写）
  List<CachedAccount> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _accounts;
    return _accounts
        .where((a) =>
            a.issuer.toLowerCase().contains(q) ||
            a.account.toLowerCase().contains(q))
        .toList();
  }

  /// 新增账户后立即在头部插入一条"未解密"元数据（扫码/手动添加秒级反馈）。
  /// 后续 reload 阶段一会用数据库全量重建覆盖。
  void insertMeta(TOTPAccount account) {
    _accounts = [
      CachedAccount(
        clientId: account.clientId,
        issuer: account.issuer,
        account: account.account,
        algorithm: account.algorithm,
        digits: account.digits,
        period: account.period,
      ),
      ..._accounts,
    ];
    // 新账户尚未同步，标记待同步（enqueue 后仍为 pending，flush 成功后更新）
    _syncStates = {..._syncStates, account.clientId: AccountSyncStatus.pending};
    _loaded = true;
    notifyListeners();
  }

  /// 两阶段重载：先元数据（快），后台逐条解密（慢）。
  /// 需要 LockService 已解锁（masterPassword 非空）。
  Future<void> reload() async {
    final pwd = LockService.instance.masterPassword;
    if (pwd == null) return;
    final rows = await AccountRepository().listCipher();

    // 阶段一：元数据立即填充（不解密，秒级）
    _accounts = rows
        .map((r) => CachedAccount(
              clientId: r.clientId,
              issuer: r.issuer,
              account: r.account,
              algorithm: r.algorithm,
              digits: r.digits,
              period: r.period,
            ))
        .toList();
    _loaded = true;
    _decrypting = rows.isNotEmpty;
    await refreshSyncStates();
    notifyListeners();

    // 阶段二：后台逐条解密（PBKDF2 每条约 1 秒），完成一条更新一条
    for (var i = 0; i < rows.length; i++) {
      try {
        final secret =
            await CryptoService.decrypt(rows[i].secretCiphertext, pwd);
        _accounts[i] = CachedAccount(
          clientId: rows[i].clientId,
          issuer: rows[i].issuer,
          account: rows[i].account,
          algorithm: rows[i].algorithm,
          digits: rows[i].digits,
          period: rows[i].period,
          secretBase32: secret,
        );
        notifyListeners();
      } catch (_) {
        // 解密失败（口令变更/数据损坏）：保留元数据，动态码保持占位
      }
    }
    _decrypting = false;
    notifyListeners();
  }

  /// 刷新每账户同步状态（入队/同步完成后由 SyncService 调用）。
  /// 判定规则：
  /// - 队列中有该 client_id → pending（待同步/重试中）
  /// - 否则 last_synced_time > 0 → backedUp（已备份）
  /// - 两者皆无 → 无状态（从未同步，不显示图标）
  Future<void> refreshSyncStates() async {
    final db = await AppDatabase.instance.database;
    final queueRows =
        await db.query('t_sync_queue', columns: ['client_id']);
    final pendingIds =
        queueRows.map((r) => r['client_id'] as String).toSet();
    final accountRows = await db.query(
      't_account',
      columns: ['client_id', 'last_synced_time'],
    );
    final states = <String, AccountSyncStatus>{};
    for (final r in accountRows) {
      final id = r['client_id'] as String;
      final lastSynced = r['last_synced_time'] as int?;
      if (pendingIds.contains(id)) {
        states[id] = AccountSyncStatus.pending;
      } else if (lastSynced != null && lastSynced > 0) {
        states[id] = AccountSyncStatus.backedUp;
      }
    }
    _syncStates = states;
    notifyListeners();
  }

  /// 上锁时清空缓存（明文不残留内存）
  void clear() {
    _accounts = const [];
    _syncStates = const {};
    _loaded = false;
    _decrypting = false;
    notifyListeners();
  }
}
