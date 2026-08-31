// lib/core/net/logging_client.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'log_redaction.dart';

/// HTTP 요청·응답을 개발 중에만 들여다보기 위한 래퍼 — 이슈 #61 로 다시 씀.
///
/// ## 무엇이 문제였나
///
/// 예전에는 URL·모든 헤더·응답 본문 800자를 `print` 로 찍었고 **빌드 모드를 가리지 않았다.**
/// Flutter 의 `print()` 는 릴리스 빌드에서도 플랫폼 로그(Android logcat / iOS oslog)에 쓴다.
/// `adb logcat` 으로 읽히고, 루팅 기기에서는 다른 앱도 읽으며, 크래시 리포터가 로그를
/// 함께 수집하는 경우가 많다.
///
/// 그래서 실제로 이런 것들이 새고 있었다.
///  - **외부 API 키** — 예전에는 이 클라이언트가 감싸는 `PlaceDetailApi` 가 관광공사를
///    직접 호출했고 키가 쿼리스트링으로 흘렀다. URL 을 찍는 순간 키가 남는다.
///    그 호출은 #40 에서 서버로 옮겼지만 **마스킹은 남긴다** — 다음에 또 그런 호출이
///    생겼을 때 이 방어가 이미 서 있어야 한다
///  - **Authorization 헤더** — 지금 사용처는 비인증이지만 이건 범용 래퍼다.
///    #11(AuthedClient)이 인증 헤더를 일원화하면서 함께 쓰면 모든 JWT 가 로그로 나간다
///  - **응답 본문** — `/auth/me` 나 `/auth/login` 을 태우면 프로필과 토큰이 그대로
///
/// ## 지금 규칙
///
///  1. **릴리스에서는 한 줄도 찍지 않는다** (`kDebugMode` 가드)
///  2. 민감 헤더·쿼리 파라미터는 **디버그에서도 가린다**.
///     개발자가 화면을 공유하거나 로그를 이슈에 붙이는 경로가 실재한다
///  3. 본문은 이름 기반으로 토큰류를 가리고 길이를 자른다. 본문 마스킹은 완전할 수 없어서
///     **본문 로깅 자체가 디버그 전용**인 것이 방어의 본체다
///
/// `print` 대신 `debugPrint` 를 쓴다 — 릴리스에서 no-op 이고 긴 줄을 잘라 준다.
/// (`avoid_print` 린트가 33건 경고하고 있었는데 `--no-fatal-warnings` 로 넘겨 아무도 안 봤다.)
class LoggingClient extends http.BaseClient {
  final http.Client _inner;
  LoggingClient(this._inner);

  /// 본문 로그의 최대 길이. 넘으면 자른다.
  static const _bodyLimit = 800;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final startedAt = DateTime.now();

    if (kDebugMode) {
      debugPrint('┌─ HTTP ${request.method} ${redactUrl(request.url)}');
      request.headers.forEach((k, v) => debugPrint('│ H: ${redactHeader(k, v)}'));
    }

    final response = await _inner.send(request);
    final bytes = await http.Response.fromStream(response);
    final body = bytes.body;

    if (kDebugMode) {
      final elapsed = DateTime.now().difference(startedAt);
      debugPrint('│ ← status: ${bytes.statusCode} (${elapsed.inMilliseconds} ms)');

      final safe = redactBody(body);
      final snippet =
          safe.length > _bodyLimit ? '${safe.substring(0, _bodyLimit)}…' : safe;
      debugPrint('│ B: ${snippet.replaceAll('\n', ' ')}');
      debugPrint('└─');
    }

    // 다시 StreamedResponse로 감싸 반환
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      bytes.statusCode,
      request: request,
      headers: bytes.headers,
      reasonPhrase: bytes.reasonPhrase,
    );
  }
}
