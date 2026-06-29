import 'dart:convert';
import 'package:http/http.dart' as http;

/// 간단 HTTP 클라이언트 (JSON POST만)
class ApiClient {
  final String baseUrl;
  final Map<String, String> defaultHeaders;

  /// JWT 토큰 공급자. 지정되면 매 요청에 `Authorization: Bearer ...` 부착.
  /// (`/api/curation/**` 는 백엔드에서 인증 필수)
  final Future<String?> Function()? tokenProvider;

  const ApiClient({
    required this.baseUrl,
    this.defaultHeaders = const {'Content-Type': 'application/json'},
    this.tokenProvider,
  });

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final token = await tokenProvider?.call();
    final merged = {
      ...defaultHeaders,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (headers != null) ...headers,
    };
    final jsonBody = body is String ? body : jsonEncode(body);
    final res = await http
        .post(uri, headers: merged, body: jsonBody)
        .timeout(timeout);
    if (res.statusCode ~/ 100 != 2) {
      throw Exception('HTTP ${res.statusCode} ${res.body}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
