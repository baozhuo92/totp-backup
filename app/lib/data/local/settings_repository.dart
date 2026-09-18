import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// 设置仓储：
/// - 服务端地址 / API Key → flutter_secure_storage（Android Keystore 加密）
/// - 非敏感开关（本地锁等）→ sqflite t_settings 表
/// 主口令永不落盘（仅存内存，见 LockService）。
class SettingsRepository {
  SettingsRepository._();

  /// 单例
  static final SettingsRepository instance = SettingsRepository._();

  static const _serverUrlKey = 'server_url';
  static const _apiKeyKey = 'api_key';

  final _secureStorage = const FlutterSecureStorage(
    // 11.x 默认即 AES-GCM + RSA 封装强加密，无需额外选项
    aOptions: AndroidOptions(),
  );

  /// 保存服务端配置（地址 + API Key）
  Future<void> saveServerConfig({
    required String serverUrl,
    required String apiKey,
  }) async {
    await _secureStorage.write(key: _serverUrlKey, value: serverUrl);
    await _secureStorage.write(key: _apiKeyKey, value: apiKey);
  }

  /// 服务端地址（未配置返回 null）
  Future<String?> getServerUrl() =>
      _secureStorage.read(key: _serverUrlKey);

  /// API Key（未配置返回 null）
  Future<String?> getApiKey() => _secureStorage.read(key: _apiKeyKey);

  /// 是否已完成服务端配置（地址非空即视为已配置）
  Future<bool> hasServerConfig() async {
    final url = await getServerUrl();
    return url != null && url.trim().isNotEmpty;
  }

  // ---- 非敏感开关（sqflite t_settings）----

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
