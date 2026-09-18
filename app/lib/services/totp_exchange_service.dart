import '../data/models/totp_account.dart';

/// otpauth URI 文本导入导出服务。
///
/// 格式：每行一个 `otpauth://totp/...` URI（与 Google Authenticator /
/// Microsoft Authenticator / 本 App 的 fromOtpauthUri 兼容）。
/// 导出为明文文本，用户需自行保管传输渠道安全（剪贴板/加密聊天）。
class TotpExchangeService {
  /// 导出：账户列表 → otpauth URI 文本（每行一个，末尾换行）
  static String exportToText(List<TOTPAccount> accounts) {
    return accounts.map((a) => a.toOtpauthUri()).join('\n');
  }

  /// 解析导入文本 → 账户列表。
  /// 空白行跳过；无效行静默跳过（不整体失败），调用方可据返回数量提示。
  static List<TOTPAccount> parseImportText(String text) {
    final accounts = <TOTPAccount>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      try {
        accounts.add(TOTPAccount.fromOtpauthUri(line));
      } on FormatException {
        // 跳过无效行（注释行/非 otpauth 内容）
      }
    }
    return accounts;
  }
}
