import 'dart:math';

/// TOTP 账户模型：内存中的明文表示。
/// 注意：secretBase32 为明文密钥，仅允许存在于内存；
/// 落库/上传前必须经 CryptoService 加密（见任务 3/4）。
class TOTPAccount {
  /// App 本地生成的 UUID v4，作为客户端幂等键（与服务端 client_id 对应）
  final String clientId;

  /// 服务商名称（如 GitHub）
  final String issuer;

  /// 账号名/邮箱
  final String account;

  /// 明文 Base32 密钥（RFC 4648）
  final String secretBase32;

  /// TOTP 哈希算法：SHA1/SHA256/SHA512
  final String algorithm;

  /// 验证码位数：6 或 8
  final int digits;

  /// 刷新周期（秒），默认 30
  final int period;

  const TOTPAccount({
    required this.clientId,
    required this.issuer,
    required this.account,
    required this.secretBase32,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  /// 创建新账户（自动生成 clientId）
  factory TOTPAccount.create({
    required String issuer,
    required String account,
    required String secretBase32,
    String algorithm = 'SHA1',
    int digits = 6,
    int period = 30,
  }) {
    return TOTPAccount(
      clientId: _generateUuidV4(),
      issuer: issuer,
      account: account,
      secretBase32: secretBase32,
      algorithm: algorithm.toUpperCase(),
      digits: digits,
      period: period,
    );
  }

  /// 从 otpauth:// URI 解析账户。
  /// 格式：otpauth://totp/{issuer}:{account}?secret=...&algorithm=...&digits=...&period=...&issuer=...
  /// 解析失败（scheme 不符/secret 缺失）抛 FormatException。
  static TOTPAccount fromOtpauthUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme.toLowerCase() != 'otpauth') {
      throw const FormatException('不是合法的 otpauth URI');
    }
    // host 为 'totp'（Android 扫码常见）或 path 首段为 totp
    final isTotp = parsed.host.toLowerCase() == 'totp' ||
        (parsed.pathSegments.isNotEmpty &&
            parsed.pathSegments.first.toLowerCase() == 'totp');
    if (!isTotp) {
      throw const FormatException('仅支持 TOTP 类型');
    }

    // secret 必填
    final secret = parsed.queryParameters['secret'];
    if (secret == null || secret.isEmpty) {
      throw const FormatException('缺少 secret 参数');
    }

    // label 定位（坑点：otpauth://totp/LABEL 中 totp 是 host/authority，
    // label 是 path 第一段；仅当 path 首段也是 'totp'（host 为空的形式）时才取第二段）
    String label = '';
    if (parsed.host.toLowerCase() == 'totp') {
      if (parsed.pathSegments.isNotEmpty) {
        label = parsed.pathSegments.first;
      }
    } else if (parsed.pathSegments.length > 1 &&
        parsed.pathSegments.first.toLowerCase() == 'totp') {
      label = parsed.pathSegments[1];
    } else if (parsed.pathSegments.isNotEmpty) {
      label = parsed.pathSegments.first;
    }

    // label：Issuer:account（有冒号拆分 issuer/account，无冒号则 issuer 为空）
    String issuer = '';
    String account = '';
    if (label.isNotEmpty) {
      final idx = label.indexOf(':');
      if (idx >= 0) {
        issuer = label.substring(0, idx);
        account = label.substring(idx + 1);
      } else {
        account = label;
      }
    }
    // query 中的 issuer 参数优先（标准规定 issuer 参数为准）
    issuer = parsed.queryParameters['issuer'] ?? issuer;

    // 可选参数：algorithm/digits/period，缺省按 RFC 6238
    final algorithm = (parsed.queryParameters['algorithm'] ?? 'SHA1').toUpperCase();
    final digits = int.tryParse(parsed.queryParameters['digits'] ?? '') ?? 6;
    final period = int.tryParse(parsed.queryParameters['period'] ?? '') ?? 30;

    if (algorithm != 'SHA1' && algorithm != 'SHA256' && algorithm != 'SHA512') {
      throw const FormatException('不支持的 algorithm');
    }
    if (digits != 6 && digits != 8) {
      throw const FormatException('digits 必须为 6 或 8');
    }
    if (period < 1) {
      throw const FormatException('period 必须大于 0');
    }

    return TOTPAccount(
      clientId: _generateUuidV4(),
      issuer: issuer,
      account: account,
      secretBase32: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }

  /// 序列化为 otpauth:// URI（导出/分享用，与 [fromOtpauthUri] 互逆）。
  /// label 使用 `issuer:account` 形式（RFC 6238/Google Authenticator 兼容），
  /// issuer 为空时 label 仅 account；issuer 参数仅在非空时附带。
  String toOtpauthUri() {
    final label = issuer.isEmpty ? account : '$issuer:$account';
    final params = <String, String>{
      'secret': secretBase32,
      'algorithm': algorithm,
      'digits': '$digits',
      'period': '$period',
    };
    if (issuer.isNotEmpty) params['issuer'] = issuer;
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return 'otpauth://totp/${Uri.encodeComponent(label)}?$qs';
  }

  /// 序列化（明文 secret，仅供加密前的中间表示/导出解密后使用）
  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'issuer': issuer,
        'account': account,
        'secret_base32': secretBase32,
        'algorithm': algorithm,
        'digits': digits,
        'period': period,
      };

  /// 反序列化
  factory TOTPAccount.fromJson(Map<String, dynamic> json) {
    return TOTPAccount(
      clientId: json['client_id'] as String,
      issuer: json['issuer'] as String,
      account: json['account'] as String,
      secretBase32: json['secret_base32'] as String,
      algorithm: json['algorithm'] as String,
      digits: json['digits'] as int,
      period: json['period'] as int,
    );
  }

  /// 生成 UUID v4（dart:math Random.secure，无需引入 uuid 依赖）
  static String _generateUuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
