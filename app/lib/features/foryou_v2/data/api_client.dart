import 'dart:convert';

import 'package:heat_trip_flutter/core/net/authed_client.dart';

/// 간단 HTTP 클라이언트 (JSON POST만)
///
/// 토큰 공급자를 직접 들고 있지 않다 — 인증 헤더 부착도 401 갱신도
/// [AuthedClient] 가 한다 (#11). `/api/curation/**` 는 백엔드에서 인증 필수다.
class ApiClient {
  final String baseUrl;
  final AuthedClient _client;

  ApiClient({required this.baseUrl, AuthedClient? client})
    : _client = client ?? AuthedClient.instance;

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _client
        .postJson(uri, body: body, headers: headers)
        .timeout(timeout);
    if (res.statusCode ~/ 100 != 2) {
      throw Exception('HTTP ${res.statusCode} ${res.body}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
