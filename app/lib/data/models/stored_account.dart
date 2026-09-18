/// 本地存储的账户行（secret 为密文）。
/// 与内存模型 TOTPAccount 分离：列表/出码需要明文 secret，
/// 由服务层在解锁时解密为 TOTPAccount 缓存（避免每秒解密）。
class StoredAccount {
  final String clientId;
  final String issuer;
  final String account;

  /// 端到端加密后的 secret（AES-256-GCM 密文，v1:base64 格式）
  final String secretCiphertext;
  final String algorithm;
  final int digits;
  final int period;
  final int createdTime;
  final int updateTime;
  final int? lastSyncedTime;

  const StoredAccount({
    required this.clientId,
    required this.issuer,
    required this.account,
    required this.secretCiphertext,
    required this.algorithm,
    required this.digits,
    required this.period,
    required this.createdTime,
    required this.updateTime,
    this.lastSyncedTime,
  });

  /// 数据库行 → 存储模型
  factory StoredAccount.fromMap(Map<String, dynamic> map) {
    return StoredAccount(
      clientId: map['client_id'] as String,
      issuer: map['issuer'] as String,
      account: map['account'] as String,
      secretCiphertext: map['secret_ciphertext'] as String,
      algorithm: map['algorithm'] as String,
      digits: map['digits'] as int,
      period: map['period'] as int,
      createdTime: map['created_time'] as int,
      updateTime: map['update_time'] as int,
      lastSyncedTime: map['last_synced_time'] as int?,
    );
  }
}
