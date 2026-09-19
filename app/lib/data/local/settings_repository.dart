import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// 设置仓储（v2）：
/// - 服务端地址 / API Key → sqflite t_settings 表
///   （本地沙箱隔离；API Key 只是访问自建备份服务的传输凭据，
///    账户密文无主口令不可解，故落库换取稳定性，
///    规避 flutter_secure_storage 普通模式 RSA 与指纹模式 AES 算法混用
///    导致插件"迁移失败→resetOnError 清空全部数据"的 bug）
/// - 指纹值（PBKDF2 指纹）→ t_settings（非敏感，主口令不可逆推）
/// - 生物识别主口令 → secure storage（必须 Keystore 强保护，
///   见 LockService：独立 storageNamespace，单一 AES-GCM 算法）
class SettingsRepository {
  SettingsRepository._();

  /// 单例
  static final SettingsRepository instance = SettingsRepository._();

  static const _serverUrlKey = 'server_url';
  static const _apiKeyKey = 'api_key';

  /// 旧版（v1）服务器配置在 secure storage 中的 key —— 仅用于一次性迁移读取
  static const _legacySecureUrlKey = 'server_url';
  static const _legacySecureApiKeyKey = 'api_key';
  static const _migrationDoneKey = 'server_config_migrated_v2';

  /// 迁移专用：旧版 secure storage 实例（RSA 算法 + 关闭 resetOnError /
  /// migrateOnAlgorithmChange）。
  /// 为什么必须如此：旧位置同时存在 RSA（server_url/api_key）与 AES
  /// （master_password_biometric）两种算法数据，若用默认配置访问会触发
  /// "算法变更→迁移→失败→清空全部数据"。禁用自动迁移与清库后，
  /// 读取失败只返回 null（旧值大概率已被插件清掉），绝不触发数据删除。
  final _legacySecureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );

  /// 保存服务端配置（地址 + API Key）→ 写入 t_settings，并清理旧 secure 残留
  Future<void> saveServerConfig({
    required String serverUrl,
    required String apiKey,
  }) async {
    await setSetting(_serverUrlKey, serverUrl);
    await setSetting(_apiKeyKey, apiKey);
    // 清理旧版 secure storage 残留（若存在）；不等待，失败无碍
    unawaited(_legacySecureStorage.delete(key: _legacySecureUrlKey));
    unawaited(_legacySecureStorage.delete(key: _legacySecureApiKeyKey));
  }

  /// 服务端地址（未配置返回 null；首次读取触发旧配置一次性迁移）
  Future<String?> getServerUrl() async {
    await _migrateLegacyServerConfig();
    return getSetting(_serverUrlKey);
  }

  /// API Key（未配置返回 null；首次读取触发旧配置一次性迁移）
  Future<String?> getApiKey() async {
    await _migrateLegacyServerConfig();
    return getSetting(_apiKeyKey);
  }

  /// 是否已完成服务端配置（地址非空即视为已配置）
  Future<bool> hasServerConfig() async {
    final url = await getServerUrl();
    return url != null && url.trim().isNotEmpty;
  }

  /// 一次性迁移旧版（secure storage）服务器配置到 t_settings。
  /// 幂等：迁移完成后写标记，避免重复读取；读不到旧值（可能已被插件清空）
  /// 则跳过，配置留空由用户重填，不阻塞任何流程。
  Future<void> _migrateLegacyServerConfig() async {
    if (await getBool(_migrationDoneKey)) return;
    String? legacyUrl;
    String? legacyKey;
    try {
      legacyUrl = await _legacySecureStorage.read(key: _legacySecureUrlKey);
      legacyKey = await _legacySecureStorage.read(key: _legacySecureApiKeyKey);
    } catch (_) {
      // 算法不匹配/密钥失效：旧值读不到，放弃迁移（安全：不删任何数据）
    }
    if (legacyUrl != null && legacyUrl.trim().isNotEmpty) {
      await setSetting(_serverUrlKey, legacyUrl.trim());
    }
    if (legacyKey != null && legacyKey.trim().isNotEmpty) {
      await setSetting(_apiKeyKey, legacyKey.trim());
    }
    try {
      await _legacySecureStorage.delete(key: _legacySecureUrlKey);
      await _legacySecureStorage.delete(key: _legacySecureApiKeyKey);
    } catch (_) {
      // 删除失败忽略（残留无害，无人再访问旧存储）
    }
    await setBool(_migrationDoneKey, true);
  }

  // ---- 通用设置（sqflite t_settings）----

  /// 读取字符串设置（缺省返回 null）
  Future<String?> getSetting(String key) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      't_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  /// 写入字符串设置
  Future<void> setSetting(String key, String value) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      't_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读取布尔设置（缺省 [def]）
  Future<bool> getBool(String key, {bool def = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      't_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return def;
    return rows.first['value'] == '1';
  }

  /// 写入布尔设置
  Future<void> setBool(String key, bool value) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      't_settings',
      {'key': key, 'value': value ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
