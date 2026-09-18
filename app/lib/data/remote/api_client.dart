import 'package:dio/dio.dart';

import '../models/totp_account.dart';

/// API 错误类型（页面只需映射为友好文案）
enum ApiErrorType { network, auth, server, parse }

/// 统一 API 异常：message 为用户可读中文提示
class ApiException implements Exception {
  final ApiErrorType type;
  final String message;

  ApiException(this.type, this.message);

  @override
  String toString() => message;
}

/// 服务端拉取的账户行（密文原样，解密在服务层完成）
class RemoteAccount {
  final String clientId;
  final String issuer;
  final String account;
  final String secretCiphertext;
  final String algorithm;
  final int digits;
  final int period;

  const RemoteAccount({
    required this.clientId,
    required this.issuer,
    required this.account,
    required this.secretCiphertext,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  /// 服务端 GET /api/accounts 返回项解析
  factory RemoteAccount.fromJson(Map<String, dynamic> json) {
    return RemoteAccount(
      clientId: json['client_id'] as String,
      issuer: json['issuer'] as String,
      account: json['account'] as String,
      secretCiphertext: json['secret_ciphertext'] as String,
      algorithm: json['algorithm'] as String,
      digits: json['digits'] as int,
      period: json['period'] as int,
    );
  }
}

/// 服务端 API 客户端（dio 封装）。
/// 单用户模式：Header `X-API-Key` 鉴权；全部方法在失败时抛 [ApiException]。
class ApiClient {
  ApiClient({required String baseUrl, required String apiKey}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {'X-API-Key': apiKey},
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        contentType: Headers.jsonContentType,
      ),
    );
  }

  late final Dio _dio;

  /// 上传/更新单个加密账户（client_id 幂等）
  /// [secretCiphertext] 必须为 CryptoService 加密后的密文
  Future<void> upsert(TOTPAccount account, String secretCiphertext) async {
    try {
      await _dio.post(
        '/api/accounts/upsert',
        data: {
          'client_id': account.clientId,
          'issuer': account.issuer,
          'account': account.account,
          'secret_ciphertext': secretCiphertext,
          'algorithm': account.algorithm,
          'digits': account.digits,
          'period': account.period,
        },
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// 删除账户（服务端软删除）
  Future<void> delete(String clientId) async {
    try {
      await _dio.delete('/api/accounts/$clientId');
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// 全量拉取备份（换机恢复用；密文原样返回）
  Future<List<RemoteAccount>> fetchAll() async {
    try {
      final resp = await _dio.get('/api/accounts');
      final items = resp.data['items'] as List<dynamic>;
      return items
          .map((e) => RemoteAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// DioException → ApiException（用户友好文案）
  ApiException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return ApiException(ApiErrorType.network, '网络连接失败，请检查网络后重试');
      case DioExceptionType.badResponse:
        if (e.response?.statusCode == 401) {
          return ApiException(ApiErrorType.auth, 'API Key 无效，请检查设置页配置');
        }
        return ApiException(
            ApiErrorType.server, '服务端返回错误（${e.response?.statusCode}）');
      default:
        return ApiException(ApiErrorType.network, '网络请求失败，请稍后重试');
    }
  }
}
