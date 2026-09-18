import 'package:sqflite/sqflite.dart';

import '../../core/crypto/crypto_service.dart';
import '../models/stored_account.dart';
import '../models/totp_account.dart';
import 'app_database.dart';

/// 本地账户仓储：纯存储层，secret 一律以密文落库。
/// 插入/更新时用主口令加密；查询返回 [StoredAccount]（密文），
/// 解密为明文 TOTPAccount 由服务层在解锁时统一完成并缓存。
class AccountRepository {
  /// 新增账户（本地生成 clientId；secret 加密后入库）
  Future<void> insert(TOTPAccount account, String masterPassword) async {
    final db = await AppDatabase.instance.database;
    final cipher =
        await CryptoService.encrypt(account.secretBase32, masterPassword);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      't_account',
      {
        'client_id': account.clientId,
        'issuer': account.issuer,
        'account': account.account,
        'secret_ciphertext': cipher,
        'algorithm': account.algorithm,
        'digits': account.digits,
        'period': account.period,
        'created_time': now,
        'update_time': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace, // client_id 幂等
    );
  }

  /// 更新账户（重新加密 secret，刷新 update_time）
  Future<void> update(TOTPAccount account, String masterPassword) async {
    final db = await AppDatabase.instance.database;
    final cipher =
        await CryptoService.encrypt(account.secretBase32, masterPassword);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      't_account',
      {
        'issuer': account.issuer,
        'account': account.account,
        'secret_ciphertext': cipher,
        'algorithm': account.algorithm,
        'digits': account.digits,
        'period': account.period,
        'update_time': now,
      },
      where: 'client_id = ?',
      whereArgs: [account.clientId],
    );
  }

  /// 删除账户（本地物理删除；服务端软删除由同步层负责）
  Future<void> delete(String clientId) async {
    final db = await AppDatabase.instance.database;
    await db.delete('t_account', where: 'client_id = ?', whereArgs: [clientId]);
  }

  /// 全量查询（密文原样返回，按 issuer/account 排序）
  Future<List<StoredAccount>> listCipher() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      't_account',
      orderBy: 'issuer COLLATE NOCASE, account COLLATE NOCASE',
    );
    return rows.map(StoredAccount.fromMap).toList();
  }

  /// 查询单个账户（密文）
  Future<StoredAccount?> getCipher(String clientId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      't_account',
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoredAccount.fromMap(rows.first);
  }

  /// 标记同步成功时间
  Future<void> markSynced(String clientId, int syncedTime) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      't_account',
      {'last_synced_time': syncedTime},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }
}
