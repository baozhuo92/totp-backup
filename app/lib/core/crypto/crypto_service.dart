import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 端到端加密服务（设计文档 §4）。
///
/// 密文格式：`v1:base64(salt(16) + nonce(12) + ciphertext + mac(16))`
/// - 密钥派生：PBKDF2-HMAC-SHA256，210000 次迭代（OWASP 推荐量级）
/// - 加密算法：AES-256-GCM（带认证标签，防篡改）
/// - 主口令仅作派生输入，服务端/数据库永远只存密文
///
/// 坑点：
/// - cryptography 2.x 的 Pbkdf2.deriveKey 以 nonce 参数承载 salt
/// - GCM 认证失败抛 SecretBoxAuthenticationError，需转为用户可读异常
/// - PBKDF2 210000 次在低端手机约数百毫秒~1 秒，属预期（仅在加锁/恢复时执行）
class CryptoService {
  CryptoService._();

  static const String _version = 'v1';
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16; // AES-GCM tag 固定 16 字节
  static const int _pbkdf2Iterations = 210000;

  /// 加密明文，返回 `v1:base64(...)` 密文
  static Future<String> encrypt(String plaintext, String masterPassword) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = await _deriveKey(masterPassword, salt);
    final box = await AesGcm.with256bits().encrypt(
          utf8.encode(plaintext),
          secretKey: key,
          nonce: nonce,
        );
    final payload = BytesBuilder()
      ..add(salt)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return '$_version:${base64Encode(payload.toBytes())}';
  }

  /// 解密密文。口令错误或数据被篡改时抛 [FormatException]（GCM 认证失败）。
  static Future<String> decrypt(String payload, String masterPassword) async {
    final sep = payload.indexOf(':');
    if (sep <= 0 || payload.substring(0, sep) != _version) {
      throw const FormatException('不支持的密文格式');
    }
    final Uint8List raw;
    try {
      raw = base64Decode(payload.substring(sep + 1));
    } on FormatException {
      throw const FormatException('密文 Base64 解码失败');
    }
    if (raw.length < _saltLength + _nonceLength + _macLength) {
      throw const FormatException('密文长度异常');
    }
    final salt = raw.sublist(0, _saltLength);
    final nonce = raw.sublist(_saltLength, _saltLength + _nonceLength);
    final cipher = raw.sublist(_saltLength + _nonceLength, raw.length - _macLength);
    final mac = Mac(raw.sublist(raw.length - _macLength));
    final key = await _deriveKey(masterPassword, salt);
    try {
      final clear = await AesGcm.with256bits().decrypt(
            SecretBox(cipher, nonce: nonce, mac: mac),
            secretKey: key,
          );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException('解密失败：主口令错误或数据已损坏');
    }
  }

  /// 派生主口令指纹（本地锁校验用，任务 6）。
  /// 格式：`v1:base64(salt(16) + sha256(keyBytes))`，不直接暴露派生密钥。
  static Future<String> deriveFingerprint(String masterPassword) async {
    final salt = _randomBytes(_saltLength);
    final key = await _deriveKey(masterPassword, salt);
    final keyBytes = await key.extractBytes();
    final digest = await Sha256().hash(keyBytes);
    return '$_version:${base64Encode(salt + digest.bytes)}';
  }

  /// 校验口令是否与指纹匹配（提取指纹中的 salt 重新派生比对）
  static Future<bool> verifyFingerprint(
      String fingerprint, String password) async {
    final sep = fingerprint.indexOf(':');
    if (sep <= 0) return false;
    final Uint8List raw;
    try {
      raw = base64Decode(fingerprint.substring(sep + 1));
    } on FormatException {
      return false;
    }
    if (raw.length < _saltLength) return false;
    final salt = raw.sublist(0, _saltLength);
    final key = await _deriveKey(password, salt);
    final keyBytes = await key.extractBytes();
    final digest = await Sha256().hash(keyBytes);
    // 注意：必须带上版本前缀，与 deriveFingerprint 的格式保持一致
    final candidate = '$_version:${base64Encode(salt + digest.bytes)}';
    return candidate == fingerprint;
  }

  /// PBKDF2 派生 256 位密钥（cryptography 包的 Pbkdf2 以 nonce 参数承载 salt）
  static Future<SecretKey> _deriveKey(String password, List<int> salt) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  /// 加密安全随机字节
  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rnd.nextInt(256)));
  }
}
