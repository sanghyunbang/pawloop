import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/logging_client.dart';

/// v2 데이터 레이어용 얇은 HTTP 클라이언트.
/// 기존 [Env.apiBase] + [LoggingClient]를 재사용한다.
/// 인증 토큰은 [token]에 주입하면 Authorization 헤더로 붙는다(공개 API는 불필요).
class V2Api {
  V2Api._();

  static final http.Client _client = LoggingClient(http.Client());
  static const Duration _timeout = Duration(seconds: 10);

  /// JWT (로그인 후 주입). 공개 엔드포인트는 null이어도 됨.
  static String? token;

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  static Future<dynamic> getJson(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('${Env.apiBase}$path').replace(queryParameters: query);
    final resp = await _client.get(uri, headers: _headers()).timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('GET $path → ${resp.statusCode}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  static Future<dynamic> postJson(String path, Object body) async {
    final uri = Uri.parse('${Env.apiBase}$path');
    final resp = await _client.post(uri, headers: _headers(), body: jsonEncode(body)).timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('POST $path → ${resp.statusCode}');
    }
    final s = utf8.decode(resp.bodyBytes);
    return s.isEmpty ? null : jsonDecode(s);
  }
}
