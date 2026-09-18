import 'package:flutter/foundation.dart';

import '../core/crypto/crypto_service.dart';
import '../data/local/account_repository.dart';
import '../data/models/totp_account.dart';
import 'lock_service.dart';

/// 会话账户缓存（ChangeNotifier 单例）：解锁后从本地库解密加载明文账户，
/// 供列表页/出码/同步使用，避免每秒刷新时重复解密（PBKDF2 开销大）。
///
/// 生命周期：解锁成功或增/改/删后调用 [reload] 刷新；
/// 上锁（lock）时清空缓存，防止内存残留明文。
class AccountCache extends ChangeNotifier {
  AccountCache._();

  /// 单例
  static final AccountCache instance = AccountCache._();

  List<TOTPAccount> _accounts = const [];
  bool _loaded = false;

  /// 明文账户列表（不可变视图）
  List<TOTPAccount> get accounts => List.unmodifiable(_accounts);

  /// 是否已从本地库加载过
  bool get loaded => _loaded;

  /// 按搜索词过滤后的账户列表（issuer/account 包含匹配，忽略大小写）
  List<TOTPAccount> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _accounts;
    return _accounts
        .where((a) =>
            a.issuer.toLowerCase().contains(q) ||
            a.account.toLowerCase().contains(q))
        .toList();
  }

  /// 重新从本地库加载并解密（跳过损坏条目）。
  /// 需要 LockService 已解锁（masterPassword 非空）。
  Future<void> reload() async {
    final pwd = LockService.instance.masterPassword;
    if (pwd == null) return;
    final rows = await AccountRepository().listCipher();
    final list = <TOTPAccount>[];
    for (final row in rows) {
      try {
        final secret = await CryptoService.decrypt(row.secretCiphertext, pwd);
        list.add(TOTPAccount(
          clientId: row.clientId,
          issuer: row.issuer,
          account: row.account,
          secretBase32: secret,
          algorithm: row.algorithm,
          digits: row.digits,
          period: row.period,
        ));
      } catch (_) {
        // 跳过解密失败的条目（口令变更/数据损坏），不阻断整体加载
      }
    }
    _accounts = list;
    _loaded = true;
    notifyListeners();
  }

  /// 上锁时清空缓存（明文不残留内存）
  void clear() {
    _accounts = const [];
    _loaded = false;
    notifyListeners();
  }
}
