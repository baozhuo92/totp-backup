import 'package:otp/otp.dart';

import '../data/models/totp_account.dart';

/// TOTP 验证码生成服务：封装 otp 包（RFC 6238 实现，社区审查）。
/// 坑点说明（已核对 otp 3.2.0 源码）：
/// - 必须传 isGoogle: true 才会对 secret 做 Base32 解码（否则按 UTF-8 字节处理，验证码错误）
/// - 默认算法是 SHA256，必须按账户显式传入算法（RFC 默认 SHA1）
/// - generateTOTPCodeString 的 time 参数单位是毫秒（内部 ~/1000）
class TotpService {
  TotpService._();

  /// 生成当前时间步的验证码（补零字符串，长度 = 账户 digits）
  static String currentCode(TOTPAccount account) {
    return OTP.generateTOTPCodeString(
      account.secretBase32,
      DateTime.now().millisecondsSinceEpoch,
      length: account.digits,
      interval: account.period,
      algorithm: _mapAlgorithm(account.algorithm),
      isGoogle: true, // 关键：Base32 secret 需解码
    );
  }

  /// 当前时间步剩余秒数（倒计时用）
  static int remainingSeconds(int period) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return period - (nowSec % period);
  }

  /// 算法字符串 → otp 包枚举（默认 SHA1，白名单外按 SHA1 处理）
  static Algorithm _mapAlgorithm(String algorithm) {
    switch (algorithm.toUpperCase()) {
      case 'SHA256':
        return Algorithm.SHA256;
      case 'SHA512':
        return Algorithm.SHA512;
      default:
        return Algorithm.SHA1;
    }
  }
}
