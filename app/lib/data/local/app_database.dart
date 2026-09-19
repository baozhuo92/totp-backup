import 'package:sqflite/sqflite.dart';

/// 本地 SQLite 数据库（App 权威数据源，本地为主）。
///
/// 三张表：
/// - t_account：账户（secret 以密文存储，绝不落明文）
/// - t_settings：设置项（本地锁指纹值、服务端地址/API Key 等；生物识别主口令
///   仍走 Keystore secure storage，见 LockService）
/// - t_sync_queue：同步失败待补推队列（任务 9 使用）
class AppDatabase {
  AppDatabase._();

  /// 单例（App 进程内共享连接）
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'totp.db';
  static const _dbVersion = 1;

  Database? _db;

  /// 获取数据库连接（懒加载，首次调用建库）
  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    // 手动拼接路径（避免额外引入 path 包；sqflite 路径接受正斜杠）
    final path = '$dir/$_dbName';
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  /// 建表迁移（v1 首次建库）
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE t_account (
        client_id TEXT PRIMARY KEY,
        issuer TEXT NOT NULL,
        account TEXT NOT NULL,
        secret_ciphertext TEXT NOT NULL,
        algorithm TEXT NOT NULL,
        digits INTEGER NOT NULL,
        period INTEGER NOT NULL,
        created_time INTEGER NOT NULL,
        update_time INTEGER NOT NULL,
        last_synced_time INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE t_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE t_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id TEXT NOT NULL,
        op TEXT NOT NULL,
        payload TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_time INTEGER NOT NULL
      )
    ''');
  }

  /// 关闭连接（测试/退出时调用）
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
