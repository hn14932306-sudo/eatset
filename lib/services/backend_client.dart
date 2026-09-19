import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Public service address only. Google credentials never enter the app build.
class BackendClient {
  BackendClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? const String.fromEnvironment('EATSET_API_BASE_URL');
  final http.Client _client;
  final String baseUrl;
  bool get isConfigured => baseUrl.trim().isNotEmpty;
  Uri _uri(String path) {
    final base = Uri.tryParse(baseUrl);
    final local =
        base != null &&
        const ['localhost', '127.0.0.1', '::1', '10.0.2.2'].contains(base.host);
    if (base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' &&
            !(base.scheme == 'http' && local && !kReleaseMode))) {
      throw const BackendException('INVALID_BACKEND');
    }
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
  }

  Future<http.Response> _request(
    String path,
    Map<String, dynamic>? body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final uri = _uri(path);
      final response =
          await (body == null
                  ? _client.get(uri)
                  : _client.post(
                      uri,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(body),
                    ))
              .timeout(timeout);
      if (response.statusCode != 200) {
        var code = 'REQUEST_FAILED';
        try {
          code =
              (jsonDecode(response.body)['error']['code'] as String?) ?? code;
        } catch (_) {}
        throw BackendException(code);
      }
      return response;
    } on BackendException {
      rethrow;
    } catch (_) {
      throw const BackendException('NETWORK_FAILED');
    }
  }

  Future<Map<String, dynamic>> json(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _request(path, body);
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const BackendException('INVALID_RESPONSE');
    }
  }

  /// [size] is only sent for non-default sizes ('thumb'); the server owns the
  /// actual pixel limits.
  Future<Uint8List> image(String token, {String? size}) async {
    final response = await _request('/v1/photo', {
      'token': token,
      if (size != null) 'size': size,
    }, timeout: const Duration(seconds: 15));
    if (!(response.headers['content-type'] ?? '').startsWith('image/') ||
        response.bodyBytes.isEmpty ||
        response.bodyBytes.length > 8 * 1024 * 1024) {
      throw const BackendException('INVALID_RESPONSE');
    }
    return response.bodyBytes;
  }

  void dispose() => _client.close();
}

class BackendException implements Exception {
  const BackendException(this.code);
  final String code;
  String get message => switch (code) {
    'CLIENT_LIMIT' || 'DAILY_LIMIT' => '目前查詢次數已達上限，請稍後再試。',
    'PLACE_NOT_FOUND' => '目前找不到這家店的最新資料。',
    'NETWORK_FAILED' => '目前沒有網路連線，請連線後再試。',
    _ => '店家資訊暫時無法更新，請稍後再試。',
  };
  @override
  String toString() => message;
}
