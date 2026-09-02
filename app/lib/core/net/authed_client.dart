// lib/core/net/authed_client.dart
//
// 인증이 필요한 모든 HTTP 요청의 **단일 진입점** — 이슈 #11.
//
// ## 무엇이 문제였나
//
// `Authorization` 헤더를 손으로 조립하는 파일이 16개였다. 각 파일이
// `TokenStorage.getToken()` 을 부르고 `'Bearer $token'` 을 직접 적었다.
// 그 상태에서는 "401 이면 갱신하고 재시도한다" 를 넣을 자리가 없다 — 16곳을 전부
// 고쳐야 하고, 저장소가 하나 바뀌면 또 16곳이다.
//
// 그리고 지금까지는 401 을 만나면 그냥 실패했다. 액세스 토큰 수명이 417일이라
// 겪은 사람이 없었을 뿐이고, #6 이 1시간으로 줄이는 순간 앱은 한 시간마다 조용히
// 망가진다.
//
// ## 규칙
//
//  1. `Authorization` 을 만드는 곳은 이 파일 하나다.
//  2. 401 → 갱신 → **정확히 1회** 재시도. 재시도가 또 401 이면 로그아웃한다.
//  3. 갱신은 **single-flight** 다(아래 참조).
//  4. 갱신 요청 자체는 `AuthedClient` 를 타지 않는다 — 태우면 갱신의 401 이 다시
//     갱신을 부르는 무한 재귀가 된다.
//  5. 로그에 토큰이 남지 않는다 — 이 클래스는 헤더를 직접 찍지 않고, 감싸는
//     `LoggingClient` 는 `redactHeader` 로 `Authorization` 값을 가린다(#61).
//  6. **저장된 토큰을 지우는 것은 401 뿐이다.** 갱신이 429·5xx·네트워크 오류로 실패하면
//     토큰을 그대로 두고 호출부에 401 을 돌려준다 — #14 가 `/auth/token/refresh` 에
//     429 를 새로 만들었고, 그것을 로그아웃으로 읽으면 잠깐의 혼잡이 재로그인 강제가
//     된다(`_RefreshResult` 참조).
//
// ## ⚠️ single-flight 가 선택이 아닌 이유
//
// 서버는 refresh 토큰을 **회전**시키고 **유예 창을 두지 않는다**(#9).
// 같은 RT 로 동시에 두 번 보내면 진 쪽이 **재사용**으로 판정되고, 재사용 감지는
// 그 사용자의 **살아 있는 RT 를 전량 폐기**한다.
//
//     만료된 AT 로 API 두 개가 동시에 401 → 각자 refresh
//       → 한쪽이 재사용 판정 → 전 기기 로그아웃
//
// 사용자에게는 서버 버그로 보인다. 그래서 진행 중인 갱신이 있으면 새로 보내지 않고
// 그 `Future` 에 합류한다. 그리고 **갱신이 실패하면 재시도하지 않는다** — 실패한
// RT 로 한 번 더 두드리는 것이 정확히 위 시나리오를 만든다. 토큰을 지우고
// 로그인 화면으로 보낸다.
//
// ## 왜 POST 도 재시도하는가 (멱등성)
//
// 401 은 인증 필터(`JWTAuthenticationFilter`)가 컨트롤러에 닿기 **전에** 끊은
// 응답이다. 즉 서버는 요청을 **처리하지 않았다** — 부수효과가 없다. 그래서
// 멱등하지 않은 POST/PUT/DELETE 도 401 에 한해 재시도해도 중복 생성이 생기지 않는다.
// 재시도 대상을 401 로만 한정하는 이유가 이것이다. 5xx·타임아웃은 서버가 처리했는지
// 알 수 없으므로 **여기서 재시도하지 않는다.**

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, immutable, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/logging_client.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/auth_tokens.dart';

/// 세션이 끝났을 때(갱신 불가·재시도 후에도 401) 불리는 훅.
///
/// 저장된 토큰을 지우는 것은 [AuthedClient] 가 이미 한다. 이 훅은 **화면 이동**용이다 —
/// 라우터(`app_router.dart`)는 #12 소유라 이 파일이 직접 import 하지 않는다.
typedef SessionExpiredHook = Future<void> Function();

/// 갱신 한 번의 결말. **"실패" 를 두 가지로 나누는 것이 이 타입의 전부다.** (#14)
///
/// 예전에는 `Future<String?>` 하나였고 `null` 이 곧 로그아웃이었다. 그 상태에서는
/// "이 refresh 토큰은 죽었다"(401)와 "지금은 서버가 못 받는다"(429·5xx·네트워크)가
/// 구분되지 않아, 잠깐의 혼잡이 **재로그인 강제**로 번역됐다.
@immutable
class _RefreshResult {
  /// 성공했을 때의 새 액세스 토큰. 실패면 null.
  final String? accessToken;

  /// 이 실패로 저장된 토큰을 지워야 하는가. **401 일 때만 true** 다.
  final bool endsSession;

  const _RefreshResult.renewed(String token)
      : accessToken = token,
        endsSession = false;

  /// 서버가 "이 자격증명으로는 안 된다" 고 확답했다(401). 세션을 끝낸다.
  const _RefreshResult.sessionOver()
      : accessToken = null,
        endsSession = true;

  /// 일시적 실패. **토큰을 보존한다** — 다음 요청이 다시 시도하면 된다.
  const _RefreshResult.tryAgainLater()
      : accessToken = null,
        endsSession = false;
}

class AuthedClient extends http.BaseClient {
  /// 실제로 바이트를 보내는 클라이언트. 테스트에서는 `MockClient` 를 꽂는다.
  final http.Client _inner;

  /// 갱신 엔드포인트를 만들 베이스 URL.
  ///
  /// `Env.apiBase` 를 안에서 읽지 않고 **주입받는다** — 그래야 유닛 테스트에서
  /// 환경 설정 없이 이 클래스를 세울 수 있다.
  final String baseUrl;

  final AuthTokenStore _store;

  /// 세션 만료 시 호출. null 이면 토큰만 지운다.
  SessionExpiredHook? onSessionExpired;

  /// 진행 중인 갱신. **single-flight 의 전부가 이 필드다.**
  /// 이 필드를 없애고 401 마다 갱신을 보내면 동시성 테스트가 갱신 5회를 관측한다.
  Future<_RefreshResult>? _refreshInFlight;

  AuthedClient({
    required http.Client inner,
    required String baseUrl,
    required AuthTokenStore store,
    this.onSessionExpired,
  }) : _inner = inner,
       baseUrl = _stripTrailingSlash(baseUrl),
       _store = store;

  /// 앱 전역 인스턴스. 로깅 래퍼(#61)와 보안 저장소(#8)를 조합한다.
  static final AuthedClient instance = AuthedClient(
    inner: LoggingClient(http.Client()),
    baseUrl: Env.apiBase,
    store: SecureAuthTokenStore(),
  );

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// 본문이 있는 요청의 기본 Content-Type. 이 문자열은 여기 한 곳에만 있다.
  static const String jsonContentType = 'application/json; charset=utf-8';

  /// 토큰 갱신 왕복의 상한.
  ///
  /// 이게 없으면 응답을 주지 않는 서버(끊긴 연결·죽은 프로세스·중간 장비)에서
  /// 갱신 future 가 **영원히** 걸립니다. 단일 비행(single-flight)이라 그 하나가
  /// 걸리면 뒤따르는 모든 401 재시도가 같은 future 를 기다리며 함께 멈춥니다 —
  /// 앱은 로딩만 돌고 사용자에게는 아무 문구도 뜨지 않습니다.
  ///
  /// 15초인 이유: 이 왕복은 사람이 기다리는 화면 뒤에 있고, 모바일 네트워크가
  /// 느려도 정상 응답은 그 안에 옵니다. 타임아웃은 실패로 분류되지만
  /// **세션 종료는 아닙니다** — 토큰을 지우지 않고 다음 요청이 다시 시도합니다.
  static const Duration refreshTimeout = Duration(seconds: 15);

  // ── 편의 메서드 ────────────────────────────────────────────────────────
  //
  // `http` 패키지의 `post(url, body: jsonEncode(x))` 는 헤더를 안 주면
  // Content-Type 을 `text/plain` 으로 붙인다. 계약은 JSON 이므로 호출부가 매번
  // 헤더를 적어야 했고, 그 반복이 곧 16개 파일이었다. 아래 메서드가 그 자리를 대신한다.

  Future<http.Response> getJson(Uri url, {Map<String, String>? headers}) =>
      get(url, headers: headers);

  Future<http.Response> postJson(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
  }) => post(
    url,
    headers: _withJsonContentType(headers),
    body: _encodeJsonBody(body),
  );

  Future<http.Response> putJson(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
  }) => put(
    url,
    headers: _withJsonContentType(headers),
    body: _encodeJsonBody(body),
  );

  Future<http.Response> patchJson(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
  }) => patch(
    url,
    headers: _withJsonContentType(headers),
    body: _encodeJsonBody(body),
  );

  Future<http.Response> deleteJson(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
  }) => delete(
    url,
    headers: body == null ? headers : _withJsonContentType(headers),
    body: _encodeJsonBody(body),
  );

  static Map<String, String> _withJsonContentType(Map<String, String>? given) {
    final headers = <String, String>{...?given};
    final hasContentType = headers.keys.any(
      (k) => k.toLowerCase() == 'content-type',
    );
    if (!hasContentType) headers['Content-Type'] = jsonContentType;
    return headers;
  }

  /// 이미 문자열이면 그대로, 아니면 JSON 으로 만든다.
  static Object? _encodeJsonBody(Object? body) {
    if (body == null) return null;
    if (body is String) return body;
    return jsonEncode(body);
  }

  // ── 본체 ───────────────────────────────────────────────────────────────

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final template = await _RequestTemplate.capture(request);

    final first = await _inner.send(template.build(await _accessToken()));
    if (first.statusCode != 401) return first;

    // 재생할 수 없는 요청(StreamedRequest)은 재시도 자체가 불가능하다.
    // 몸통을 이미 흘려보냈으므로 그대로 돌려준다.
    if (!template.replayable) return first;

    // 401 은 계약상 본문이 없지만, 스트림은 비워 연결을 놓아 준다.
    await first.stream.drain<void>();

    final renewal = await _refreshAccessToken();
    if (renewal.accessToken == null) {
      // 갱신 실패. **여기서 다시 갱신하지 않는다** — 실패한 RT 를 한 번 더 보내는 것이
      // 재사용 판정을 만들고 전 기기를 끊는다.
      //
      // 다만 **세션을 끝내는 것은 401 뿐이다.** 429·5xx·네트워크 오류는 "지금은 안 된다"
      // 이지 "이 RT 는 죽었다" 가 아니다. 그것으로 토큰을 지우면 잠깐의 혼잡이 재로그인
      // 강제로 번역된다 — #14 가 /auth/token/refresh 에 429 를 새로 만들었으므로 이 구분이
      // 없으면 공용 NAT 뒤에서 정상 사용자가 로그아웃된다.
      if (renewal.endsSession) {
        await _endSession();
      }
      return _emptyUnauthorized(first);
    }

    final second = await _inner.send(template.build(renewal.accessToken!));
    if (second.statusCode != 401) return second;

    // 새 AT 로도 401 이면 더 해 볼 것이 없다. 여기서 멈추지 않으면 무한 루프다.
    await second.stream.drain<void>();
    await _endSession();
    return _emptyUnauthorized(second);
  }

  Future<String?> _accessToken() async {
    final token = await _store.readAccessToken();
    return (token == null || token.isEmpty) ? null : token;
  }

  /// 진행 중인 갱신이 있으면 그 `Future` 를 그대로 돌려준다(single-flight).
  ///
  /// `async` 를 붙이지 않은 것은 의도다. 필드 검사와 대입이 **await 없이**
  /// 한 호흡에 끝나야 두 호출자가 사이를 비집고 들어오지 못한다.
  Future<_RefreshResult> _refreshAccessToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final started = _performRefresh();
    _refreshInFlight = started;
    started.whenComplete(() {
      // 그사이 새 갱신이 시작됐을 수 있으니 내가 넣은 것일 때만 비운다.
      if (identical(_refreshInFlight, started)) _refreshInFlight = null;
    });
    return started;
  }

  /// `POST /auth/token/refresh`. 성공하면 새 액세스 토큰, 실패하면 그 실패의 **성격**.
  ///
  /// **`_inner` 로 직접 보낸다** — `this` 로 보내면 갱신의 401 이 또 갱신을 부른다.
  ///
  /// ## 세션을 끝내는 것은 401 뿐이다 (#14)
  ///
  /// 예전에는 200 이 아닌 모든 응답이 `null` 이었고, 호출부는 그것을 전부 "세션 종료"로
  /// 읽어 저장된 토큰을 지웠다. #14 가 이 경로에 rate limit 을 새로 걸면서 **429** 가
  /// 처음으로 나올 수 있게 됐는데, 429 는 "잠시 후 다시" 라는 일시적 신호다. 그것을
  /// 로그아웃으로 번역하면 멀쩡한 refresh 토큰이 사라진다 — 실측으로 429 한 번에
  /// `store.clear()` 가 불리고 세션 만료 훅이 돌았다.
  ///
  /// 인증 버킷은 소셜 코드 교환과 **공유**하므로(`PublicSecurityProperties.authMaxRequests`)
  /// 공용 NAT·사무실 Wi-Fi 뒤에서 로그인이 몰리면 그 뒤의 다른 사용자가 갱신에서 429 를
  /// 받는다. 그 사람이 재로그인을 강요당할 이유가 없다.
  Future<_RefreshResult> _performRefresh() async {
    final refreshToken = await _store.readRefreshToken();
    // 보낼 RT 가 없다 = 이 기기에 세션이 없다. 지울 것도 없지만 상태는 '끝'이다.
    if (refreshToken == null || refreshToken.isEmpty) {
      return const _RefreshResult.sessionOver();
    }

    try {
      final res = await _inner
          .post(
            Uri.parse('$baseUrl/auth/token/refresh'),
            headers: const {'Content-Type': jsonContentType},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(refreshTimeout);

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[AuthedClient] 갱신 거절: ${res.statusCode}');
        }
        // 401 만 "이 RT 로는 다시 안 된다" 는 확답이다(만료·폐기·재사용이 전부 401).
        // 그 밖(429·5xx·400 류)은 토큰의 유효성에 대해 아무 말도 하지 않는다.
        return res.statusCode == 401
            ? const _RefreshResult.sessionOver()
            : const _RefreshResult.tryAgainLater();
      }

      final tokens = AuthTokens.tryParse(res.body);
      // 200 인데 파싱이 안 된다 = 계약 위반이지 토큰이 죽은 것이 아니다.
      if (tokens == null) return const _RefreshResult.tryAgainLater();

      // 회전된 새 RT 를 반드시 교체 저장한다. 옛 값을 남기면 다음 갱신이
      // 폐기된 토큰을 보내 재사용 판정에 걸린다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return _RefreshResult.renewed(tokens.accessToken);
    } catch (e) {
      // 예외 메시지에 요청 본문(= RT 원문) 조각이 섞일 수 있어 타입만 남긴다.
      if (kDebugMode) {
        debugPrint('[AuthedClient] 갱신 중 오류: ${e.runtimeType}');
      }
      // 네트워크가 끊겼다고 로그인 상태를 버리지 않는다. 비행기 모드에서 앱을 열었다는
      // 이유로 재로그인을 강요하는 것이 정확히 그 동작이다.
      return const _RefreshResult.tryAgainLater();
    }
  }

  /// 저장된 토큰을 지우고 세션 만료를 알린다.
  Future<void> _endSession() async {
    await _store.clear();
    try {
      await onSessionExpired?.call();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthedClient] 세션 만료 훅 실패: ${e.runtimeType}');
      }
    }
  }

  /// 계약상 401 은 본문이 없다. 호출부가 기대하는 모양 그대로 돌려준다.
  http.StreamedResponse _emptyUnauthorized(http.StreamedResponse original) =>
      http.StreamedResponse(
        Stream<List<int>>.empty(),
        401,
        request: original.request,
        headers: original.headers,
        reasonPhrase: original.reasonPhrase,
      );

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 재시도를 위한 요청 스냅샷
// ─────────────────────────────────────────────────────────────────────────

/// 같은 요청을 **여러 번 조립**하기 위한 틀.
///
/// `http` 의 `BaseRequest` 는 한 번 보내면 finalize 되어 재사용할 수 없다.
/// 원본을 그대로 다시 보내면
/// `StateError: Can't finalize a finalized Request.`(http 1.4.0
/// `lib/src/base_request.dart:118`)가 난다. 특히 `MultipartRequest` 는 파일
/// 스트림이 소진돼 두 번째 전송이 애초에 불가능하다.
///
/// 그래서 본문을 **바이트로 붙잡아 두고** 시도할 때마다 새 request 를 만든다.
class _RequestTemplate {
  final http.BaseRequest _original;

  /// `http.Request` 의 본문.
  final Uint8List? _bodyBytes;

  /// `http.MultipartRequest` 의 파일 파트(메모리에 올려 둔 사본).
  final List<_CapturedFile>? _files;

  /// 두 번 이상 보낼 수 있는가.
  final bool replayable;

  _RequestTemplate._(
    this._original, {
    Uint8List? bodyBytes,
    List<_CapturedFile>? files,
    required this.replayable,
  }) : _bodyBytes = bodyBytes,
       _files = files;

  static Future<_RequestTemplate> capture(http.BaseRequest request) async {
    if (request is http.MultipartRequest) {
      // 파일 스트림은 한 번만 읽을 수 있다. 재시도에 대비해 메모리로 옮긴다.
      // 업로드 크기만큼 메모리를 쓴다 — 앱의 업로드는 사진 몇 장 규모라 감당된다.
      // 수백 MB 를 다루게 되면 여기부터 다시 설계해야 한다.
      final captured = <_CapturedFile>[];
      for (final file in request.files) {
        captured.add(
          _CapturedFile(
            field: file.field,
            filename: file.filename,
            contentType: file.contentType,
            bytes: await file.finalize().toBytes(),
          ),
        );
      }
      return _RequestTemplate._(request, files: captured, replayable: true);
    }

    if (request is http.Request) {
      return _RequestTemplate._(
        request,
        bodyBytes: Uint8List.fromList(request.bodyBytes),
        replayable: true,
      );
    }

    // StreamedRequest 등 되감을 수 없는 몸통. 한 번만 보낸다.
    return _RequestTemplate._(request, replayable: false);
  }

  /// [accessToken] 을 붙인 **새** request 를 만든다.
  http.BaseRequest build(String? accessToken) {
    final original = _original;

    if (original is http.MultipartRequest) {
      final rebuilt = http.MultipartRequest(original.method, original.url)
        ..fields.addAll(original.fields)
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection;
      // multipart 는 boundary 가 들어간 Content-Type 을 스스로 만든다.
      // 여기에 JSON 기본값을 얹으면 서버가 몸통을 못 읽는다.
      rebuilt.headers.addAll(_authHeaders(original.headers, accessToken));
      for (final f in _files!) {
        rebuilt.files.add(
          http.MultipartFile.fromBytes(
            f.field,
            f.bytes,
            filename: f.filename,
            contentType: f.contentType,
          ),
        );
      }
      return rebuilt;
    }

    if (original is http.Request) {
      final rebuilt = http.Request(original.method, original.url)
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection;
      rebuilt.headers.addAll(
        _authHeaders(original.headers, accessToken, hasBody: _bodyBytes!.isNotEmpty),
      );
      rebuilt.bodyBytes = _bodyBytes;
      return rebuilt;
    }

    // 재생 불가 — 원본에 헤더만 얹어 그대로 보낸다.
    final merged = _authHeaders(original.headers, accessToken);
    original.headers
      ..clear()
      ..addAll(merged);
    return original;
  }

  /// 원본 헤더 + 기본값 + `Authorization`.
  ///
  /// **`Authorization` 문자열을 만드는 곳은 앱 전체에서 여기 한 줄뿐이다**(완료 조건 1).
  /// 호출부가 직접 넣은 `Authorization` 이 있어도 저장소의 토큰이 이긴다 — 두 출처가
  /// 공존하면 어느 쪽이 만료됐는지 아무도 모르게 된다.
  static Map<String, String> _authHeaders(
    Map<String, String> original,
    String? accessToken, {
    bool hasBody = false,
  }) {
    final headers = <String, String>{...original};

    bool has(String name) =>
        headers.keys.any((k) => k.toLowerCase() == name.toLowerCase());

    if (!has('Accept')) headers['Accept'] = 'application/json';
    if (hasBody && !has('Content-Type')) {
      headers['Content-Type'] = AuthedClient.jsonContentType;
    }

    headers.removeWhere((k, _) => k.toLowerCase() == 'authorization');
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    return headers;
  }
}

/// 재시도에 대비해 메모리에 붙잡아 둔 multipart 파일 파트.
class _CapturedFile {
  final String field;
  final String? filename;
  final MediaType? contentType;
  final Uint8List bytes;

  const _CapturedFile({
    required this.field,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });
}
