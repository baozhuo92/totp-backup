import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local/account_repository.dart';
import '../data/local/app_database.dart';
import '../data/local/settings_repository.dart';
import '../data/models/totp_account.dart';
import '../data/remote/api_client.dart';

/// 队列操作类型
enum SyncOp { add, update, delete }

/// 同步状态（供 UI 常驻指示：AppBar 图标/角标）
enum SyncStatus { idle, syncing, success, failed }

/// 自动备份同步服务（单例，ChangeNotifier）。
///
/// 设计要点：
/// - 本地增/改/删先写入 t_sync_queue（payload 保存**密文** secret，不落明文）
/// - flush 时逐个调用服务端接口；成功删除队列行并标记 last_synced_time，
///   失败累加 retry_count 留队（下次 flush 重试）
/// - 上传的 secret_ciphertext 与本地库同一份密文，恢复端用相同主口令即可解密
/// - 网络失败不阻塞本地操作；服务端未配置时 flush 直接跳过
/// - 通过 [status]/[pendingCount] 对外暴露同步进度，UI 监听刷新
class SyncService extends ChangeNotifier {
  SyncService._();

  /// 单例
  static final SyncService instance = SyncService._();

  /// 避免并发 flush（重复触发时合并为一次）
  bool _flushing = false;

  SyncStatus _status = SyncStatus.idle;
  int _pendingCount = 0;
  String? _lastError;
  DateTime? _lastSyncTime;

  /// 当前同步状态（UI 常驻指示用）
  SyncStatus get status => _status;

  /// 待同步队列条数（>0 表示还有未成功上传的变更）
  int get pendingCount => _pendingCount;

  /// 最近一次失败原因（status==failed 时有效）
  String? get lastError => _lastError;

  /// 最近一次成功同步时间
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 刷新待同步计数（enqueue/删除队列后调用）
  Future<void> refreshPending() async {
    _pendingCount = await _countPending();
    notifyListeners();
  }

  /// 增/改后入队（同 client_id 已有队列记录时覆盖为 UPDATE，避免重复堆积）
  Future<void> enqueueAddOrUpdate(TOTPAccount account) async {
    final db = await AppDatabase.instance.database;
    // 读取本地密文（与上传内容一致）
    final stored = await AccountRepository().getCipher(account.clientId);
    if (stored == null) return; // 本地不存在（理论上不会发生）
    final payload = jsonEncode({
      'issuer': stored.issuer,
      'account': stored.account,
      'secret_ciphertext': stored.secretCiphertext,
      'algorithm': stored.algorithm,
      'digits': stored.digits,
      'period': stored.period,
    });
    final existing = await db.query(
      't_sync_queue',
      columns: ['id'],
      where: 'client_id = ? AND op != ?',
      whereArgs: [account.clientId, SyncOp.delete.name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        't_sync_queue',
        {'op': SyncOp.update.name, 'payload': payload},
        where: 'client_id = ? AND op != ?',
        whereArgs: [account.clientId, SyncOp.delete.name],
      );
    } else {
      await db.insert('t_sync_queue', {
        'client_id': account.clientId,
        'op': SyncOp.add.name,
        'payload': payload,
        'retry_count': 0,
        'created_time': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await refreshPending();
  }

  /// 删除后入队（服务端软删除；payload 不需要）
  Future<void> enqueueDelete(String clientId) async {
    final db = await AppDatabase.instance.database;
    // 若存在未同步的 ADD/UPDATE 队列行，直接移除（本地删除覆盖了变更）
    await db.delete(
      't_sync_queue',
      where: 'client_id = ? AND op != ?',
      whereArgs: [clientId, SyncOp.delete.name],
    );
    await db.insert('t_sync_queue', {
      'client_id': clientId,
      'op': SyncOp.delete.name,
      'payload': null,
      'retry_count': 0,
      'created_time': DateTime.now().millisecondsSinceEpoch,
    });
    await refreshPending();
  }

  /// 队列中待同步的条目数
  Future<int> _countPending() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('t_sync_queue', columns: ['id']);
    return rows.length;
  }

  /// 尝试清空队列（一次网络往返逐条处理）。
  /// 服务端未配置或无队列时直接返回 true；失败条目重试计数 +1 后停止本轮。
  /// 返回是否全部成功（供调用方决定是否弹提示）。
  Future<bool> flush() async {
    if (_flushing) return true; // 已有 flush 在跑，本轮合并
    _flushing = true;
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      final configured = await SettingsRepository.instance.hasServerConfig();
      if (!configured) {
        _status = SyncStatus.idle;
        await refreshPending();
        return true;
      }
      final serverUrl = await SettingsRepository.instance.getServerUrl();
      final apiKey = await SettingsRepository.instance.getApiKey();
      if (serverUrl == null || apiKey == null) {
        _status = SyncStatus.idle;
        await refreshPending();
        return true;
      }

      final client = ApiClient(baseUrl: serverUrl, apiKey: apiKey);
      final db = await AppDatabase.instance.database;
      final rows = await db.query('t_sync_queue', orderBy: 'id ASC');
      if (rows.isEmpty) {
        _status = SyncStatus.success;
        _lastSyncTime = DateTime.now();
        await refreshPending();
        notifyListeners();
        return true;
      }

      for (final row in rows) {
        final id = row['id'] as int;
        final clientId = row['client_id'] as String;
        final op = row['op'] as String;
        try {
          if (op == SyncOp.delete.name) {
            await client.delete(clientId);
          } else {
            final payload =
                jsonDecode(row['payload'] as String) as Map<String, dynamic>;
            final account = TOTPAccount(
              clientId: clientId,
              issuer: payload['issuer'] as String,
              account: payload['account'] as String,
              secretBase32: payload['secret_ciphertext'] as String,
              algorithm: payload['algorithm'] as String,
              digits: payload['digits'] as int,
              period: payload['period'] as int,
            );
            await client.upsert(account, payload['secret_ciphertext'] as String);
            // 标记本地同步时间（仅 ADD/UPDATE 需要）
            await AccountRepository()
                .markSynced(clientId, DateTime.now().millisecondsSinceEpoch);
          }
          // 成功：移除队列行
          await db.delete('t_sync_queue', where: 'id = ?', whereArgs: [id]);
          _pendingCount--;
          notifyListeners();
        } on ApiException catch (e) {
          // 失败：retry_count +1，保留队列；停止本轮（避免网络故障时空转）
          final retry = (row['retry_count'] as int) + 1;
          await db.update(
            't_sync_queue',
            {'retry_count': retry},
            where: 'id = ?',
            whereArgs: [id],
          );
          _status = SyncStatus.failed;
          _lastError = e.message;
          await refreshPending();
          notifyListeners();
          return false;
        }
      }
      _status = SyncStatus.success;
      _lastSyncTime = DateTime.now();
      await refreshPending();
      notifyListeners();
      return true;
    } finally {
      _flushing = false;
    }
  }
}
