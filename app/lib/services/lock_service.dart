import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../core/crypto/crypto_service.dart';
import '../data/local/settings_repository.dart';

/// 本地锁服务（单例，App 进程内状态）。
///
/// 设计要点（任务 6）：
/// - 主口令默认**仅存内存**（进程被杀即需重新输入）
/// - 指纹解锁启用时：主口令以 biometric secure storage 存储
///   （Android Keystore AES-GCM + 生物识别门闩，读取须通过指纹）
/// - 解锁校验用 PBKDF2 指纹（CryptoService.deriveFingerprint），不存明文口令
class LockService {
  LockService._();

  /// 单例
  static final LockService instance = LockService._();

  static const _fingerprintKey = 'master_fingerprint';
  static const _biometricEnabledKey = 'biometric_enabled';
  static const _biometricPwdKey = 'master_password_biometric';

  final _localAuth = LocalAuthentication();

  /// 内存主口令（进程内有效）
  String? _masterPassword;

  /// 本次会话是否已解锁
  bool _unlocked = false;

  bool get isUnlocked => _unlocked;

  /// 内存主口令（解密 secret / 加密 secret 用；null 表示未解锁）
  String? get masterPassword => _masterPassword;

  /// 是否已完成首次设置（指纹存在即已配置主口令）
  Future<bool> isConfigured() async {
    final fp = await SettingsRepository.instance.getSetting(_fingerprintKey);
    return fp != null && fp.isNotEmpty;
  }

  /// 首次设置主口令（或重置）。
  /// [enableBiometric] 为 true 时同时以生物识别保护方式存储主口令（供指纹解锁）。
  Future<void> setupMasterPassword(
    String password, {
    bool enableBiometric = false,
  }) async {
    final fp = await CryptoService.deriveFingerprint(password);
    await SettingsRepository.instance.setSetting(_fingerprintKey, fp);
    if (enableBiometric) {
      await _writeBiometricPassword(password);
      await SettingsRepository.instance.setBool(_biometricEnabledKey, true);
    } else {
      await SettingsRepository.instance.setBool(_biometricEnabledKey, false);
    }
    _masterPassword = password;
    _unlocked = true;
  }

  /// 主口令解锁（校验指纹一致后放行）
  Future<bool> unlockWithPassword(String password) async {
    final fp = await SettingsRepository.instance.getSetting(_fingerprintKey);
    if (fp == null || fp.isEmpty) return false;
    final ok = await CryptoService.verifyFingerprint(fp, password);
    if (ok) {
      _masterPassword = password;
      _unlocked = true;
    }
    return ok;
  }

  /// 设备是否支持生物识别（指纹）
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// 指纹解锁：读取 biometric secure storage 中的主口令（触发系统指纹验证）。
  /// 指纹取消/失败/未启用返回 false。
  Future<bool> unlockWithBiometric() async {
    final enabled =
        await SettingsRepository.instance.getBool(_biometricEnabledKey);
    if (!enabled) return false;
    try {
      final pwd = await _readBiometricPassword();
      if (pwd == null || pwd.isEmpty) return false;
      _masterPassword = pwd;
      _unlocked = true;
      return true;
    } catch (_) {
      // 用户取消或验证失败
      return false;
    }
  }

  /// 主动上锁（清除内存口令）
  void lock() {
    _unlocked = false;
    _masterPassword = null;
  }

  /// 以生物识别保护方式写入主口令（enforceBiometrics：写入也需指纹授权）
  Future<void> _writeBiometricPassword(String password) async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions.biometric(enforceBiometrics: true),
    );
    await storage.write(key: _biometricPwdKey, value: password);
  }

  /// 读取生物识别保护的主口令（触发系统指纹验证）
  Future<String?> _readBiometricPassword() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions.biometric(enforceBiometrics: true),
    );
    return storage.read(key: _biometricPwdKey);
  }
}
